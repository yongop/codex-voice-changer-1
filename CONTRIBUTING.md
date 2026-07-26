# Contributing

버그 제보와 개선 제안을 환영합니다. 음성·모델·체크포인트·빌드 산출물은
이슈나 Pull Request에 첨부하지 말아 주세요.

## 개발 환경

1. `README.md`의 요구 사항을 확인합니다.
2. RVC 통합 작업이 필요할 때만 공식 규약을 읽고
   `./Scripts/setup-runtime.sh --accept-tsukuyomi-terms`를 실행합니다.
3. 변경 전후에 `swift test`를 실행합니다.
4. 제출 전에 `./Scripts/audit-public-tree.sh`로 공개 대상 파일을 검사합니다.

기본 테스트는 모델 없이 실행할 수 있어야 합니다. 모델이 필요한 테스트는
`CVS_RUN_RVC_INTEGRATION_TEST=1`처럼 명시적인 환경 변수로만 활성화해 주세요.

## Pull Request

- 한 PR에는 가능한 한 하나의 목적만 담아 주세요.
- 사용자 동작이나 요구 사항이 바뀌면 README도 함께 갱신해 주세요.
- 오디오 실시간 스레드에는 동적 할당, 파일 I/O, 잠금 대기 작업을 추가하지
  말아 주세요.
- 제3자 코드·모델·에셋을 추가하면 출처, 버전, 라이선스와 재배포 조건을
  `ThirdPartyLicenses/`에 기록해 주세요.
- 생성형 또는 변환 음성 샘플을 공개해야 한다면 먼저 모든 원음과 모델의
  이용 조건을 확인하고 필요한 크레딧을 표시해 주세요.
