import Foundation

struct KoreanStrings: AppStringsProviding {
  let languageMenuTitle = "언어"
  let languageSystemOption = "시스템 설정 따름"

  let errorAlertTitle = "RVC를 시작하지 못했습니다"
  let okButton = "확인"
  let captureTargetTitle = "캡처할 앱"
  let refreshRunningApps = "실행 중인 앱 새로고침"

  let activityOff = "RVC 엔진 꺼짐"
  let activityPreparing = "RVC 엔진 가동 준비 중…"
  let activityActive = "RVC 엔진 가동 중"
  let activityFailed = "RVC 엔진 오류 · 원음 출력 중"

  let consentTitle = "시작하기 전 이용규약 동의"
  let consentBody = """
    이 앱은 츠쿠요미짱 공식 RVC 모델을 사용합니다. RVC 기능을 사용하려면 공식 배포 \
    페이지와 최신 이용규약을 확인하고 명시적으로 동의해야 합니다.
    """
  let consentChecklistTitle = "확인할 내용"
  let consentChecklistCredit = "변환한 음성을 공개할 때 실제 원음과 공식 모델을 함께 밝혀야 합니다."
  let consentChecklistRights = "원음의 권리와 이용 조건은 사용자가 별도로 확인해야 합니다."
  let consentChecklistPriority = "공식 최신 이용규약이 이 앱의 요약보다 우선합니다."
  let consentOpenModelPage = "공식 배포 페이지 열기"
  let consentOpenTerms = "공식 이용규약 전문 열기"
  let consentAcceptButton = "공식 이용규약에 동의하고 시작"

  func consentRecordNote(revision: String) -> String {
    "아래 버튼을 누르면 \(revision) 검토본을 기준으로 공식 이용규약에 동의한 것으로 이 Mac에 기록됩니다."
  }

  let creditIncluded = """
    이 소프트웨어에는 프리 소재 캐릭터 「つくよみちゃん」(© Rei Yumesaki)이 무료 공개한 \
    RVC 모델이 포함되어 있습니다.
    """
  let creditVoice = "음성 변환: つくよみちゃん公式RVCモデル（通常1／CV.夢前黎）"
  let creditModelPage = "공식 배포 페이지"
  let creditTerms = "공식 이용규약"
  let creditCompliance = """
    모델 사용 시 공식 RVC 모델 이용규약을 준수해야 하며, 변환 음성 공개 시 원음 출처와 \
    모델을 함께 표기해야 합니다.
    """
  let creditAccessibility = """
    사용 보이스: つくよみちゃん公式RVCモデル 通常1, CV.夢前黎. 모델 사용 시 공식 \
    이용규약을 준수해야 합니다.
    """

  let setupSectionTitle = "설정 순서"
  let setupHint = "각 단계에 마우스를 올리면 자세한 설명이 표시됩니다. 클릭하면 그 설명이 고정됩니다."
  let setupOpenAudioPrivacy = "시스템 오디오 권한 설정 열기"
  let setupOpenFilesPrivacy = "파일 접근 권한 설정 열기"

  let setupStep1Title = "권한 요청 허가"
  let setupStep1Detail = """
    RVC를 처음 켤 때 macOS가 ‘시스템 오디오 녹음’ 권한을 요청합니다. \
    이 앱은 선택한 앱의 출력만 캡처하며 마이크는 사용하지 않습니다. \
    허용한 뒤에도 소리가 나오지 않으면 앱을 완전히 종료하고 다시 실행해 주세요.
    """
  let setupStep2Title = "파일 접근 허가"
  let setupStep2Detail = """
    변환 엔진은 프로젝트 폴더의 ‘.rvc_env’와 모델 파일을 직접 읽습니다. \
    프로젝트가 문서·데스크탑·iCloud 폴더 안에 있으면 macOS가 폴더 접근 권한을 \
    요청하므로 허용해 주세요. 거부하면 RVC를 켤 때 런타임을 찾지 못했다는 오류가 납니다.
    """
  let setupStep3Title = "ChatGPT 음성 대화(Live) 켜기"
  let setupStep3Detail = """
    ChatGPT에서 음성 대화를 먼저 시작해 마이크를 활성화합니다. \
    이 앱의 ‘캡처할 앱’에서도 같은 앱을 선택해야 그 앱의 출력이 캡처됩니다. \
    ChatGPT 앱 내 설정의 음성 추천 값은 ‘Sol’입니다.
    """
  let setupStep4Title = "음성 분리 켜기"
  let setupStep4Detail = """
    음성 대화가 켜진 상태에서 메뉴 막대의 제어 센터를 열고 \
    ‘마이크 모드 → 음성 분리’를 선택합니다. 스피커로 나간 변환 음성이 다시 \
    마이크로 들어가 ChatGPT가 자기 목소리를 받아 적는 것을 막아 줍니다. \
    마이크를 음소거하지 않아도 됩니다.
    """
  let setupStep5Title = "RVC 켜기"
  let setupStep5Detail = """
    준비가 끝나면 ‘RVC ON’을 누릅니다. RVC가 켜진 동안 대상 앱의 직접 출력은 \
    음소거되고 이 앱이 변환 음성을 재생합니다. 모델 로딩·처리 지연·변환 실패 시에는 \
    같은 시점의 원음으로 자연스럽게 전환됩니다.
    """

  func setupStepAccessibilityLabel(index: Int, title: String) -> String {
    "\(index)단계, \(title)"
  }

  let errorTermsRequired = "공식 RVC 모델 이용규약에 먼저 동의해 주세요."
  let errorSelectTargetApp = "먼저 캡처할 앱을 선택해 주세요."
  let errorUnsupportedSystem = "이 앱은 macOS 14.2 이상이 필요합니다."
  let errorNoAudioProcess = """
    선택한 앱의 오디오 프로세스를 찾지 못했습니다. 대상 앱에서 소리를 한 번 재생한 뒤 \
    다시 시도해 주세요.
    """
  let errorInvalidTap = "선택한 앱의 시스템 오디오 캡처를 만들지 못했습니다."
  let errorInvalidAggregateDevice = "캡처용 비공개 오디오 장치를 만들지 못했습니다."
  let errorInvalidAudioFormat = "캡처된 오디오 형식을 재생할 수 없습니다."
  let errorBufferAllocation = "실시간 오디오 버퍼를 할당하지 못했습니다."
  let errorProcessorAllocation = "RVC 출력 처리기를 만들지 못했습니다."

  let operationStartCapture = "실시간 앱 오디오 캡처 시작"
  let operationCreateTap = "선택한 앱의 오디오 탭 생성"
  let operationReadTapFormat = "오디오 탭 형식 읽기"
  let operationReadTapUID = "오디오 탭 식별자 읽기"
  let operationCreateAggregateDevice = "오디오 탭용 가상 장치 생성"
  let operationFindAudioProcess = "앱의 오디오 프로세스 검색"
  let operationQueryProcessListSize = "Core Audio 프로세스 목록 크기 확인"
  let operationReadProcessList = "Core Audio 프로세스 목록 읽기"
  let operationReadProcessBundleID = "오디오 프로세스 번들 ID 읽기"

  func coreAudioFailure(
    operation: String,
    code: String,
    status: Int32
  ) -> String {
    "\(operation)에 실패했습니다. (Core Audio \(code), \(status))"
  }
}
