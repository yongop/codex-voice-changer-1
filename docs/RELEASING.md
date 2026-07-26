# 공개 및 릴리스 체크리스트

## 공개 경계

| 구분 | 공개 여부 | 위치 또는 예시 |
| --- | --- | --- |
| 앱 소스·테스트·문서 | 공개 | `Sources/`, `Tests/`, `Runtime/`, `Scripts/` |
| 모델 메타데이터·고지 | 공개 | `Resources/Models/`, `ThirdPartyLicenses/` |
| 공식 RVC 모델 가중치 | Git에 비공개 | `.training_cache/tsukuyomi_rvc/models/` |
| RVC/HuBERT/RMVPE 다운로드 | Git에 비공개 | `.training_cache/tsukuyomi_rvc/RVC/` |
| 개인·외부 음성 원본 | 비공개 | `voice_analysis_work/`, WAV/MP3/M4A |
| 연구·학습 산출물 | 비공개 | `voice_training/`, `outputs/`, 체크포인트 |
| 로컬 가상환경·빌드 결과 | 비공개 | `.rvc_env/`, `.build/`, `dist/` |
| 환경 파일·키·인증서 | 비공개 | `.env*`, PEM/KEY/P12/mobileprovision |

`.gitignore`는 위 비공개 경로와 파일 형식을 차단합니다. 새 파일을 추가한
뒤에는 `git status --ignored`와 `./Scripts/audit-public-tree.sh`를 모두
확인합니다.

## GitHub 최초 공개 전

1. `git diff --cached`로 공개될 전체 내용을 사람이 직접 검토합니다.
2. `./Scripts/audit-public-tree.sh`가 성공하는지 확인합니다.
3. `swift test`가 성공하는지 확인합니다.
4. GitHub 저장소에서 Secret scanning과 Private vulnerability reporting을
   가능한 경우 활성화합니다.
5. 저장소 설명에 Apple Silicon/macOS 전용임을 밝힙니다.
6. GitHub Topics에는 `macos`, `swift`, `voice-conversion`, `rvc` 정도만
   사용하고 공식 프로젝트로 오해할 표현은 피합니다.

## 소스 릴리스와 앱 바이너리

GitHub 저장소와 소스 아카이브에는 모델 파일을 넣지 않습니다. 사용자가
공식 배포처의 현재 규약을 직접 확인한 뒤 설정 스크립트로 받도록 합니다.

`Scripts/build-app.sh`로 만든 앱 번들에는 공식 모델이 포함됩니다. 공식
규약은 모델의 소프트웨어 동봉을 허용하지만, 다음 조건을 계속 지켜야 합니다.

- 공식 배포 페이지를 배포원으로 표시
- `つくよみちゃん公式RVCモデル（CV.夢前黎）` 크레딧 표시
- 공식 모델 이용규약을 모델 부분에 그대로 적용
- 사용 전에 볼 수 있는 위치에 안내 표시
- 유료 배포 시 공식 무개조 모델 자체에 대가를 부과하지 않음

현재 앱은 프로젝트 바깥으로 옮기면 `.rvc_env`를 찾을 수 없으므로 독립
실행형 바이너리 릴리스 대상이 아닙니다. GitHub Releases에는 우선 소스
릴리스만 제공하세요. 나중에 Python 런타임을 앱 내부에 재배치할 때는 모든
Python 의존성의 라이선스 파일까지 번들에 포함하고, 새 Mac 사용자 계정에서
오프라인 실행과 코드 서명을 다시 검증해야 합니다.

## 공식 규약 재확인

릴리스할 때마다 아래 두 페이지의 수정일과 내용을 다시 확인합니다.

- https://tyc.rei-yumesaki.net/work/software/rvc/
- https://tyc.rei-yumesaki.net/work/software/rvc/terms/

이 프로젝트의 고지는 2026-07-27에, 2026-06-27 개정 공식 RVC 모델
이용규약을 기준으로 검토했습니다. 공식 페이지의 최신 내용이 항상
우선합니다.
