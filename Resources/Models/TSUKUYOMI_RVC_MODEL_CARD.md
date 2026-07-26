# Tsukuyomi-chan official RVC model: 通常1 +5

이 앱은 `つくよみちゃん公式RVCモデル` 버전 1.0.0의 `通常1`만
사용합니다. 체크포인트 자체는 소스 저장소에 포함하지 않으며 공식
배포처에서 내려받은 파일의 SHA-256을 검증합니다.

- Conversion model: RVC v2, F0-conditioned, 40 kHz
- Pitch estimator: RMVPE
- Pitch shift: +5 semitones
- Retrieval index: disabled
- Streaming backend: PyTorch MPS Float16
- Device block: 220 ms
- SOLA crossfade: 50 ms (40 ms matching buffer + 10 ms search)
- Retained input context: 2.5 seconds
- Buffered scheduling reserve: 60 ms
- Optional coloration/DSP: disabled
- RVC source commit:
  `4338f12c3c28c80b3ac015e2d0df66c41592746d`
- Model SHA-256:
  `cd4996435d0e9c9f93858a13d9ddf5442a011388478daab1f732e0ac2b2c4020`
- HuBERT SHA-256:
  `cc8c20f4b90a520757260197a3ff2505705a7adbd20ad9eeaa4e1a9b38442ef5`
- RMVPE SHA-256:
  `6d62215f4306e3ca278246188607209f09af3dc77ed4232efdd069798c4ec193`

## Streaming behavior

The worker is warmed before converted output becomes ready. Presentation
latency is calculated as one 220 ms input block plus the measured first
inference and a 60 ms scheduling reserve. The renderer always maintains a
dry delay at the same presentation time.

On the target Apple M2, a 30-block steady-state run measured p50 134.38 ms,
p95 156.87 ms, and maximum 163.34 ms. That leaves 56.66 ms before the next
220 ms input deadline. The separate 60 ms presentation reserve absorbs output
scheduling jitter without adding work to the inference path.

During loading, a failed conversion, or a short inference underrun, the
renderer crossfades to the delayed source instead of emitting silence. It
does not continuously discard late converted frames. If an underrun lasts
120 ms, the stream state is reset once at the newest input edge, remains on
the dry fallback while the reserve is rebuilt, and then crossfades back to
converted output.

## Credit and terms

- Model: `つくよみちゃん公式RVCモデル（通常1／CV.夢前黎）`
- Character/material attribution: `つくよみちゃん` (© Rei Yumesaki)
- Official model:
  <https://tyc.rei-yumesaki.net/work/software/rvc/>
- Terms:
  <https://tyc.rei-yumesaki.net/work/software/rvc/terms/>

This model is not covered by the application's MIT License. The official
terms apply to the model portion. They require both the actual conversion
source and the official RVC model to be credited when converted audio is
published. The current official terms take precedence over this summary.
