# Codex Voice Changer 1

Apple Silicon Mac에서 **선택한 앱의 출력 음성만** 캡처해
`つくよみちゃん公式RVCモデル（通常1）`로 실시간 변환하는 오픈 소스
macOS 앱입니다. 마이크나 가상 오디오 드라이버는 사용하지 않으며, 변환이
늦거나 실패하면 같은 시점의 원음으로 자연스럽게 전환합니다.

> [!IMPORTANT]
> 소스 코드는 MIT 라이선스이지만, 츠쿠요미짱 공식 RVC 모델은 별도의
> [공식 이용규약](https://tyc.rei-yumesaki.net/work/software/rvc/terms/)을
> 따릅니다. 모델 파일은 이 저장소에 포함되지 않으며, 처음 설정할 때 공식
> 배포처에서 직접 내려받습니다. 설치 스크립트는 이용규약 동의를 대신
> 기록하지 않으며, 앱을 처음 실행하면 RVC를 사용하기 전에 공식 페이지와
> 이용규약을 확인하고 `공식 이용규약에 동의하고 시작` 버튼을 눌러야 합니다.

## 주요 기능

- macOS Process Tap으로 특정 앱의 시스템 오디오만 캡처
- RVC v2 + RMVPE, `通常1`, 피치 `+5` 반음의 고정 프리셋
- PyTorch MPS Float16 기반 Apple Silicon 실시간 추론
- 실측 추론 시간에 맞춘 적응형 지터 버퍼와 무음 구간 추론 우회
- 로딩·언더런·오류 시 presentation time을 맞춘 원음 폴백
- 변환/원음 전환 시 짧은 크로스페이드로 클릭과 무음 최소화
- 모든 오디오 처리를 로컬에서 수행하며 앱 자체는 네트워크를 사용하지 않음

## 요구 사항

- Apple Silicon Mac
- macOS 14.2 이상
- Xcode 16.3 이상 또는 Swift 6.1 이상 도구 모음
- [uv](https://docs.astral.sh/uv/)와 Git
- 최초 설정·빌드·설치 시 약 3 GB의 여유 공간과 인터넷 연결
- 최초 실행 시 macOS의 **시스템 오디오 녹음** 권한

Intel Mac은 현재 지원하지 않습니다.

공개 준비 시점(2026-07-27)의 검증 환경은 Xcode 26.4.1, Swift 6.3.1,
Python 3.11.15입니다. 패키지는 호환 범위를 넓히기 위해 Swift 6.1을
최소 도구 버전으로 유지합니다.

## 빠른 시작

저장소를 받은 뒤 프로젝트 루트에서 실행합니다.

```sh
./Scripts/setup-runtime.sh

./Scripts/install-app.sh
./Scripts/run-app.sh
```

설정 스크립트는 다음 항목만 로컬 전용 경로에 준비합니다.

- 츠쿠요미짱 공식 RVC 모델: 공식 배포처에서 다운로드
- 고정된 RVC 소스 커밋과 HuBERT/RMVPE 파일: SHA-256 검증
- Python 3.11 가상환경과 고정 버전 런타임 의존성

설정 단계에서는 이용규약 동의를 받거나 저장하지 않습니다. 동의는 앱의
최초 실행 화면에서 공식 링크와 주요 조건을 확인한 뒤 명시적으로 진행합니다.

서명된 빌드 산출물은 `dist/Codex Voice Changer 1.app.zip`에 보관되고,
설치된 앱은 `/Applications/Codex Voice Changer 1.app`에 있습니다.
`Documents`가 iCloud File Provider로 관리되더라도 Finder 확장 속성이
코드서명을 깨뜨리지 않도록 앱은 임시 로컬 경로에서 서명한 뒤 ZIP으로
보존하고 `/Applications`에서 다시 검증합니다.

현재 빌드는 프로젝트의 `.rvc_env`를 사용하므로, 프로젝트 폴더를 이동하거나
삭제하거나 앱만 다른 Mac으로 복사하는 독립 실행형 배포는 아직 지원하지
않습니다. `/Applications`에 쓸 수 없는 환경에서는 설치와 실행 모두에
`CVS_APP_INSTALL_DIR`을 지정할 수 있습니다.

```sh
CVS_APP_INSTALL_DIR="$HOME/Applications" ./Scripts/install-app.sh
CVS_APP_INSTALL_DIR="$HOME/Applications" ./Scripts/run-app.sh
```

## 사용법

처음 실행하면 공식 배포 페이지와 이용규약을 읽고
`공식 이용규약에 동의하고 시작`을 누릅니다. 이후 메인 화면의
`설정 순서` 카드가 다음 다섯 단계를 안내하며, 각 단계에 마우스를 올리면
자세한 설명이, 클릭하면 그 설명이 고정된 채 표시됩니다.

1. **권한 요청 허가** — RVC를 처음 켤 때 요청되는 시스템 오디오 녹음 권한을
   허용합니다.
2. **파일 접근 허가** — 프로젝트가 문서·데스크탑·iCloud 폴더 안에 있으면
   `.rvc_env`와 모델 파일을 읽기 위한 폴더 접근 권한을 허용합니다.
3. **ChatGPT 음성 대화(Live) 켜기** — 대상 앱에서 음성 대화를 시작하고, 이 앱의
   `캡처할 앱`에서 같은 앱을 선택합니다.
4. **음성 분리 켜기** — 제어 센터에서 `마이크 모드 → 음성 분리`를 선택합니다.
5. **RVC 켜기** — `RVC ON`을 누릅니다.

RVC가 켜진 동안 대상 앱의 직접 출력은 음소거되고 이 앱이 변환 음성을
재생합니다. 모델 로딩, 짧은 처리 지연 또는 변환 실패 시에는 원음이
대신 출력됩니다.

### 스피커로 쓸 때의 에코 되먹임

스피커로 들으면 변환된 음성이 다시 마이크로 들어가 대화 상대 앱이 자기
목소리를 입력으로 받아버릴 수 있습니다. 4단계의 **음성 분리**가 macOS의
음향 에코 제거를 활성화해 이를 막아 주므로, 마이크를 음소거하지 않고도
양방향 대화를 계속할 수 있습니다. 마이크 모드는 마이크를 사용 중인 앱에
대해서만 제어 센터에 나타납니다.

권한을 허용했는데 소리가 나오지 않으면 앱을 완전히 종료한 뒤 다시
실행하거나, 앱 안의 `시스템 오디오 권한 설정 열기`를 사용해 권한을
확인하세요.

## 검증

모델 없이 실행되는 기본 테스트:

```sh
swift test
```

`swift test`에는 `XCTest`가 포함된 전체 Xcode가 필요합니다. Command Line
Tools만 설치된 환경에서는 앱을 `swift build`로 빌드할 수 있지만 테스트
타깃은 컴파일되지 않습니다.

설정을 마친 Apple Silicon Mac에서 실제 RVC 작업자까지 확인하는 통합 테스트:

```sh
CVS_RUN_RVC_INTEGRATION_TEST=1 \
  swift test --filter RVCStreamingEngineTests/testWorkerIntegrationWhenRequested
```

GitHub에 올리기 전 공개 대상 파일을 다시 검사하려면:

```sh
./Scripts/audit-public-tree.sh
```

## 프로젝트 구성

```text
Config/                앱 Info.plist
Resources/Models/      모델 메타데이터와 모델 카드(가중치 없음)
Runtime/               공개 가능한 RVC 스트리밍 작업자와 의존성 목록
Scripts/               설정, 빌드, 실행, 공개 전 검사 스크립트
Sources/                Swift/C/C++ 앱 소스
Tests/                  단위 및 선택적 통합 테스트
ThirdPartyLicenses/     RVC 및 공식 모델 고지
```

공개 저장소에는 위 소스와 문서만 들어갑니다. 다음 항목은 로컬 전용이며
`.gitignore`로 차단됩니다.

- `.training_cache/`, `.rvc_env/` 등 다운로드된 모델·런타임·가상환경
- `dist/`, `.build/`, `outputs/` 등 앱·빌드·학습 산출물
- `voice_analysis_work/`, `voice_training/`, `VOICE_RESEARCH.md` 등
  개인 음성, 외부 원본, 실험·분석 자료
- WAV/MP3/M4A, 체크포인트, Core ML 모델과 각종 인증서·환경 파일

자세한 배포 경계와 릴리스 전 확인 사항은
[`docs/RELEASING.md`](docs/RELEASING.md)에 정리되어 있습니다.

## 츠쿠요미짱 크레딧과 사용 조건

이 소프트웨어는 프리 소재 캐릭터 `つくよみちゃん`(© Rei Yumesaki)이
무료 공개한 RVC 모델을 사용합니다.

이 저장소와 앱은 츠쿠요미짱 프로젝트의 공식 앱이나 제휴 제품이 아닙니다.

- 모델: `つくよみちゃん公式RVCモデル（通常1／CV.夢前黎）`
- [공식 모델 배포 페이지](https://tyc.rei-yumesaki.net/work/software/rvc/)
- [공식 RVC 모델 이용규약](https://tyc.rei-yumesaki.net/work/software/rvc/terms/)

변환한 음성을 공개할 때는 실제 변환 원음과 공식 모델을 모두 밝혀야 합니다.
예시는 다음과 같습니다.

```text
원음: 본인 음성
음성 변환: つくよみちゃん公式RVCモデル（通常1）
```

다른 사람의 음성이나 음성 합성 소프트웨어 출력을 사용할 때는 원음 쪽
권리와 이용규약도 별도로 확인해야 합니다. 정치·종교·사상에 대한 찬반을
촉구하거나 실재 인물·단체·상품을 공격하는 활동 등 공식 규약의 금지
사항도 적용됩니다. 이 README의 요약보다 공식 최신 규약이 우선합니다.

## 라이선스

앱 소스는 [MIT License](LICENSE)로 공개합니다. 이 라이선스는 츠쿠요미짱
공식 RVC 모델, HuBERT/RMVPE 가중치 또는 제3자 코드의 권리를 대신하지
않습니다. 고정 버전과 제3자 고지는
[`ThirdPartyLicenses`](ThirdPartyLicenses)에서 확인할 수 있습니다.

기여 방법은 [CONTRIBUTING.md](CONTRIBUTING.md), 보안 문제 제보 방법은
[SECURITY.md](SECURITY.md), 오디오·개인정보 처리 방식은
[PRIVACY.md](PRIVACY.md)를 참고하세요.
