#!/usr/bin/env python3
"""Binary PCM streaming worker for the bundled Tsukuyomi-chan RVC preset.

Protocol on stdin/stdout (little-endian):

* startup response: ``RDY2`` + uint32 sample-rate + uint32 block-frames
  + uint32 stable-warmup-microseconds
* input frame: ``FRM1`` + block-frames float32 samples
* output frame: ``OUT1`` + uint32 inference-microseconds + float32 samples
* reset request/response: ``RST1`` / ``ACK1``
* shutdown request: ``STP1``
* failure response: ``ERR1`` + uint32 UTF-8 byte count + message

All upstream logging is redirected to stderr so stdout remains binary-clean.
"""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import os
import platform
import struct
import sys
import time
from pathlib import Path

os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

import numpy as np
import torch
import torch.nn.functional as torch_functional
from torchaudio.transforms import Resample

torch.set_num_interop_threads(1)

MODEL_SHA256 = (
    "cd4996435d0e9c9f93858a13d9ddf5442a011388478daab1f732e0ac2b2c4020"
)


def configure_latency_critical_qos() -> None:
    """Keep the streaming thread out of App Nap/background scheduling."""
    if platform.system() != "Darwin":
        return
    try:
        qos_class_user_interactive = 0x21
        pthread = ctypes.CDLL(None)
        pthread.pthread_set_qos_class_self_np.argtypes = [
            ctypes.c_uint,
            ctypes.c_int,
        ]
        pthread.pthread_set_qos_class_self_np.restype = ctypes.c_int
        result = pthread.pthread_set_qos_class_self_np(
            qos_class_user_interactive,
            0,
        )
        if result != 0:
            print(
                f"Could not set latency-critical QoS (error {result}).",
                file=sys.stderr,
                flush=True,
            )
    except (AttributeError, OSError) as error:
        print(
            f"Could not set latency-critical QoS: {error}",
            file=sys.stderr,
            flush=True,
        )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_exact(stream, count: int) -> bytes | None:
    result = bytearray()
    while len(result) < count:
        block = stream.read(count - len(result))
        if not block:
            return None if not result else bytes(result)
        result.extend(block)
    return bytes(result)


def read_exact_into(stream, buffer: bytearray) -> bool:
    """Fill a reusable protocol buffer without allocating a payload object."""
    view = memoryview(buffer)
    offset = 0
    while offset < len(view):
        count = stream.readinto(view[offset:])
        if not count:
            return False
        offset += count
    return True


def write_error(stream, error: BaseException) -> None:
    message = f"{type(error).__name__}: {error}".encode(
        "utf-8",
        errors="replace",
    )
    try:
        stream.write(b"ERR1" + struct.pack("<I", len(message)) + message)
        stream.flush()
    except BrokenPipeError:
        pass


class RuntimeConfig:
    def __init__(self, device: torch.device, is_half: bool) -> None:
        self.device = device
        self.is_half = is_half
        self.cuda_graph = False


class StreamingRVCProcessor:
    def __init__(
        self,
        rvc_root: Path,
        model_path: Path,
        sample_rate: int,
        pitch: int,
        block_seconds: float,
        crossfade_seconds: float,
        extra_seconds: float,
        warmup_iterations: int,
    ) -> None:
        if not torch.backends.mps.is_available():
            raise RuntimeError("Apple MPS is unavailable.")
        if sample_rate < 16_000:
            raise ValueError("Sample rate must be at least 16 kHz.")
        if sha256(model_path) != MODEL_SHA256:
            raise RuntimeError("Tsukuyomi-chan 通常1 model SHA-256 mismatch.")

        self.device = torch.device("mps")
        self.sample_rate = sample_rate
        self.rvc_root = rvc_root
        self.zc = max(1, sample_rate // 100)
        self.block_frame = (
            round(block_seconds * sample_rate / self.zc) * self.zc
        )
        self.block_frame_16k = 160 * self.block_frame // self.zc
        self.crossfade_frame = (
            round(crossfade_seconds * sample_rate / self.zc) * self.zc
        )
        self.sola_buffer_frame = min(self.crossfade_frame, 4 * self.zc)
        self.sola_search_frame = self.zc
        self.extra_frame = (
            round(extra_seconds * sample_rate / self.zc) * self.zc
        )
        self.skip_head = self.extra_frame // self.zc
        self.return_length = (
            self.block_frame
            + self.sola_buffer_frame
            + self.sola_search_frame
        ) // self.zc
        if self.block_frame <= 0 or self.sola_buffer_frame <= 0:
            raise ValueError("Block and crossfade durations must be positive.")

        sys.path.insert(0, str(rvc_root))
        from infer.rtrvc import RVC

        self.rvc = RVC(
            pitch,
            0,
            str(model_path),
            "",
            0.0,
            RuntimeConfig(self.device, is_half=True),
        )

        self.model_sample_rate = int(self.rvc.tgt_sr)
        total_frames = (
            self.extra_frame
            + self.crossfade_frame
            + self.sola_search_frame
            + self.block_frame
        )
        self.input_overlap = torch.zeros(
            2 * self.zc,
            device=self.device,
            dtype=torch.float32,
        )
        self.block_input = torch.empty(
            self.block_frame,
            device=self.device,
            dtype=torch.float32,
        )
        self.resample_input = torch.zeros(
            self.block_frame + 2 * self.zc,
            device=self.device,
            dtype=torch.float32,
        )
        self.input_wav_resampled = torch.zeros(
            160 * total_frames // self.zc,
            device=self.device,
            dtype=torch.float32,
        )
        self.next_input_wav_resampled = torch.zeros_like(
            self.input_wav_resampled
        )
        self.sola_buffer = torch.zeros(
            self.sola_buffer_frame,
            device=self.device,
            dtype=torch.float32,
        )
        self.sola_denominator = torch.ones(
            1,
            1,
            self.sola_buffer_frame,
            device=self.device,
            dtype=torch.float32,
        )
        self.fade_in = (
            torch.sin(
                0.5
                * np.pi
                * torch.linspace(
                    0,
                    1,
                    steps=self.sola_buffer_frame,
                    device=self.device,
                    dtype=torch.float32,
                )
            )
            ** 2
        )
        self.fade_out = 1 - self.fade_in
        self.silent_output = np.zeros(self.block_frame, dtype=np.float32)
        self.output_host = torch.empty(
            self.block_frame,
            device="cpu",
            dtype=torch.float32,
        )
        self.output_numpy = self.output_host.numpy()
        # Codex voice output contains long, near-digital-silence gaps. Avoid
        # running HuBERT + RMVPE + the synthesizer for inaudible blocks while
        # retaining two RVC blocks after speech so phrase endings and breaths
        # decay naturally. The -80 dBFS RMS gate is far below quiet speech.
        self.silence_rms_squared = 1e-8
        self.silence_peak = 5e-4
        self.silence_hangover_blocks = max(
            2,
            round(0.35 / self.block_duration_seconds),
        )
        self.silence_hangover_remaining = 0
        self.pending_silent_frames_16k = 0
        self.input_resampler = Resample(
            orig_freq=sample_rate,
            new_freq=16_000,
            dtype=torch.float32,
        ).to(self.device)
        self.output_resampler = (
            Resample(
                orig_freq=self.model_sample_rate,
                new_freq=sample_rate,
                dtype=torch.float32,
            ).to(self.device)
            if self.model_sample_rate != sample_rate
            else None
        )

        # Compile every MPS graph used by the steady-state shape before the
        # app switches from its time-aligned dry fallback to RVC output.
        phase = np.arange(self.block_frame, dtype=np.float32)
        warmup = 0.01 * np.sin(
            2 * np.pi * 160 * phase / sample_rate
        ).astype(np.float32)
        warmup_microseconds = []
        for _ in range(max(1, warmup_iterations)):
            started = time.perf_counter_ns()
            self.process(warmup)
            warmup_microseconds.append(
                (time.perf_counter_ns() - started) // 1_000
            )
        self.stable_warmup_microseconds = min(
            warmup_microseconds[-1],
            0xFFFFFFFF,
        )
        self.reset()

    @property
    def block_duration_seconds(self) -> float:
        return self.block_frame / self.sample_rate

    def reset(self) -> None:
        self.input_overlap.zero_()
        self.resample_input.zero_()
        self.input_wav_resampled.zero_()
        self.next_input_wav_resampled.zero_()
        self.sola_buffer.zero_()
        self.rvc.cache_pitch.zero_()
        self.rvc.cache_pitchf.zero_()
        self.silence_hangover_remaining = 0
        self.pending_silent_frames_16k = 0
        if torch.backends.mps.is_available():
            torch.mps.synchronize()

    def should_bypass_silence(self, input_audio: np.ndarray) -> bool:
        peak = max(
            -float(np.min(input_audio, initial=0.0)),
            float(np.max(input_audio, initial=0.0)),
        )
        mean_square = float(np.dot(input_audio, input_audio) / input_audio.size)
        silent = (
            peak <= self.silence_peak
            and mean_square <= self.silence_rms_squared
        )
        if not silent:
            self.silence_hangover_remaining = self.silence_hangover_blocks
            return False
        if self.silence_hangover_remaining > 0:
            self.silence_hangover_remaining -= 1
            return False
        return True

    def flush_pending_silence(self) -> None:
        pending = min(
            self.pending_silent_frames_16k,
            self.input_wav_resampled.shape[0],
        )
        if pending <= 0:
            return
        if pending >= self.input_wav_resampled.shape[0]:
            self.input_wav_resampled.zero_()
        else:
            self.next_input_wav_resampled[:-pending].copy_(
                self.input_wav_resampled[pending:]
            )
            self.next_input_wav_resampled[-pending:].zero_()
            (
                self.input_wav_resampled,
                self.next_input_wav_resampled,
            ) = (
                self.next_input_wav_resampled,
                self.input_wav_resampled,
            )
        self.input_overlap.zero_()
        self.resample_input.zero_()
        self.sola_buffer.zero_()
        pitch_shift = min(
            pending // 160,
            self.rvc.cache_pitch.shape[0],
        )
        if pending >= self.input_wav_resampled.shape[0]:
            self.rvc.cache_pitch.zero_()
            self.rvc.cache_pitchf.zero_()
        elif pitch_shift > 0:
            self.rvc.cache_pitch[:-pitch_shift].copy_(
                self.rvc.cache_pitch[pitch_shift:].clone()
            )
            self.rvc.cache_pitch[-pitch_shift:].fill_(1)
            self.rvc.cache_pitchf[:-pitch_shift].copy_(
                self.rvc.cache_pitchf[pitch_shift:].clone()
            )
            self.rvc.cache_pitchf[-pitch_shift:].zero_()
        self.pending_silent_frames_16k = 0

    def process(self, input_audio: np.ndarray) -> np.ndarray:
        if input_audio.shape != (self.block_frame,):
            raise ValueError(
                f"Expected {self.block_frame} input samples, "
                f"received {input_audio.shape}."
            )
        if not np.isfinite(input_audio).all():
            input_audio = np.nan_to_num(
                input_audio,
                copy=False,
                nan=0.0,
                posinf=1.0,
                neginf=-1.0,
            )

        if self.should_bypass_silence(input_audio):
            self.pending_silent_frames_16k = min(
                self.input_wav_resampled.shape[0],
                self.pending_silent_frames_16k + self.block_frame_16k,
            )
            return self.silent_output

        with torch.inference_mode():
            self.flush_pending_silence()
            self.block_input.copy_(torch.from_numpy(input_audio))
            block = self.block_input
            self.resample_input[: 2 * self.zc].copy_(self.input_overlap)
            self.resample_input[2 * self.zc :].copy_(block)
            self.input_overlap.copy_(block[-2 * self.zc :])

            self.next_input_wav_resampled[
                : -self.block_frame_16k
            ].copy_(
                self.input_wav_resampled[self.block_frame_16k :]
            )
            resampled = self.input_resampler(self.resample_input)[160:]
            self.next_input_wav_resampled[
                -resampled.shape[0] :
            ].copy_(resampled)
            (
                self.input_wav_resampled,
                self.next_input_wav_resampled,
            ) = (
                self.next_input_wav_resampled,
                self.input_wav_resampled,
            )

            inferred = self.rvc.infer(
                self.input_wav_resampled,
                self.block_frame_16k,
                self.skip_head,
                self.return_length,
                "rmvpe",
            )
            if self.output_resampler is not None:
                inferred = self.output_resampler(inferred)

            correlation_input = inferred[
                None,
                None,
                : self.sola_buffer_frame + self.sola_search_frame,
            ]
            numerator = torch_functional.conv1d(
                correlation_input,
                self.sola_buffer[None, None, :],
            )
            denominator = torch.sqrt(
                torch_functional.conv1d(
                    correlation_input**2,
                    self.sola_denominator,
                )
                + 1e-8
            )
            offset = int(torch.argmax(numerator[0, 0] / denominator[0, 0]))
            inferred = inferred[offset:]
            inferred[: self.sola_buffer_frame] *= self.fade_in
            inferred[: self.sola_buffer_frame] += (
                self.sola_buffer * self.fade_out
            )
            self.sola_buffer.copy_(
                inferred[
                    self.block_frame :
                    self.block_frame + self.sola_buffer_frame
                ]
            )
            output = inferred[: self.block_frame].float()
            output = torch.nan_to_num(
                output,
                nan=0.0,
                posinf=1.0,
                neginf=-1.0,
            ).clamp(-1, 1)
            self.output_host.copy_(output)
            return self.output_numpy


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rvc-root", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--sample-rate", type=int, required=True)
    parser.add_argument("--pitch", type=int, default=5)
    parser.add_argument("--block-seconds", type=float, default=0.22)
    parser.add_argument("--crossfade-seconds", type=float, default=0.05)
    # HuBERT re-encodes the whole context window every block, so the extra
    # context length dominates per-block inference time. 1.2 s keeps ample
    # left context while roughly halving the 2.5 s default's compute.
    parser.add_argument("--extra-seconds", type=float, default=1.2)
    parser.add_argument("--warmup-iterations", type=int, default=3)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    binary_input = sys.stdin.buffer
    binary_output = sys.stdout.buffer
    # Upstream RVC uses print() for diagnostics. Keep the protocol clean.
    sys.stdout = sys.stderr
    configure_latency_critical_qos()

    try:
        rvc_root = Path(args.rvc_root).resolve()
        # RVC lazily resolves HuBERT/RMVPE assets relative to its repository.
        # This is a dedicated worker process, so set the directory once instead
        # of changing it around every 220 ms inference call.
        os.chdir(rvc_root)
        processor = StreamingRVCProcessor(
            rvc_root=rvc_root,
            model_path=Path(args.model).resolve(),
            sample_rate=args.sample_rate,
            pitch=args.pitch,
            block_seconds=args.block_seconds,
            crossfade_seconds=args.crossfade_seconds,
            extra_seconds=args.extra_seconds,
            warmup_iterations=args.warmup_iterations,
        )
        binary_output.write(
            b"RDY2"
            + struct.pack(
                "<III",
                processor.sample_rate,
                processor.block_frame,
                processor.stable_warmup_microseconds,
            )
        )
        binary_output.flush()

        byte_count = processor.block_frame * np.dtype("<f4").itemsize
        payload_buffer = bytearray(byte_count)
        audio = np.frombuffer(payload_buffer, dtype="<f4")
        while True:
            command = read_exact(binary_input, 4)
            if command is None:
                break
            if command == b"STP1":
                break
            if command == b"RST1":
                processor.reset()
                binary_output.write(b"ACK1")
                binary_output.flush()
                continue
            if command != b"FRM1":
                raise RuntimeError(f"Unknown worker command: {command!r}")

            if not read_exact_into(binary_input, payload_buffer):
                raise EOFError("Incomplete PCM input block.")
            started = time.perf_counter_ns()
            output = processor.process(audio)
            elapsed_microseconds = min(
                (time.perf_counter_ns() - started) // 1_000,
                0xFFFFFFFF,
            )
            binary_output.write(
                b"OUT1" + struct.pack("<I", elapsed_microseconds)
            )
            binary_output.write(
                memoryview(output.astype("<f4", copy=False)).cast("B")
            )
            binary_output.flush()
    except BaseException as error:
        print(
            f"RVC streaming worker failed: {type(error).__name__}: {error}",
            file=sys.stderr,
            flush=True,
        )
        write_error(binary_output, error)
        raise


if __name__ == "__main__":
    main()
