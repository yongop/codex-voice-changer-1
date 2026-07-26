# RVC runtime bridge

이 디렉터리는 공개 저장소와 앱 빌드에 필요한 최소 Python 런타임 파일만
포함합니다.

- `rvc_stream_worker.py`: Swift 앱과 바이너리 PCM 프로토콜로 통신하는 작업자
- `requirements.txt`: Apple Silicon에서 검증한 Python 3.11 의존성

작업자는 고정 크기 MPS/호스트 버퍼를 재사용하며, `-80 dBFS` 이하의 무음이
이어질 때 두 블록의 자연스러운 꼬리 이후 신경망 추론을 건너뜁니다. 음성이
돌아오면 누적된 무음 컨텍스트를 한 번에 반영한 뒤 동일한 RVC 경로를
재개합니다.

공식 모델, HuBERT, RMVPE와 RVC upstream 소스는 저장소에 포함하지 않습니다.
`Scripts/setup-runtime.sh`가 각 공식 배포처에서 받아 SHA-256을 검증한 뒤
`.training_cache/`에 보관합니다.
