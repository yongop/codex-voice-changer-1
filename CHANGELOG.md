# Changelog

이 프로젝트는 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/) 형식을
따르며, 버전은 [Semantic Versioning](https://semver.org/lang/ko/)을
사용합니다.

## [Unreleased]

### Added

- 앱 최초 실행 시 공식 RVC 모델 이용규약 링크와 명시적 동의 화면
- 현재 검토 버전 기준의 로컬 동의 기록과 이전 버전 무효화

### Changed

- 런타임 설정 명령에서 이용규약 동의 인자를 제거하고 동의 시점을 앱
  최초 실행으로 이동
- 모델 ZIP의 비 UTF-8 파일명과 무관하게 체크포인트를 SHA-256으로 선택
- File Provider 폴더에서도 임시 경로에서 앱을 서명해 ZIP으로 보존하고
  `/Applications` 설치본을 별도로 검증

## [1.0.0] - 2026-07-27

### Added

- 특정 macOS 앱의 출력만 캡처하는 Process Tap
- 츠쿠요미짱 공식 RVC `通常1` 실시간 MPS 변환
- 원음 폴백, 크로스페이드와 장기 언더런 복구
- 재현 가능한 공식 모델·RVC 런타임 설정 및 SHA-256 검증
- 공개 저장소용 라이선스, 제3자 고지, 개인정보·보안·기여 문서
