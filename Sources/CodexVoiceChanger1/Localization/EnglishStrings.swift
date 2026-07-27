import Foundation

struct EnglishStrings: AppStringsProviding {
  let languageMenuTitle = "Language"
  let languageSystemOption = "Match system setting"

  let errorAlertTitle = "Couldn’t start RVC"
  let okButton = "OK"
  let captureTargetTitle = "App to capture"
  let refreshRunningApps = "Refresh running apps"

  let activityOff = "RVC engine off"
  let activityPreparing = "Starting the RVC engine…"
  let activityActive = "RVC engine running"
  let activityFailed = "RVC engine error · playing original audio"

  let consentTitle = "Agree to the terms before starting"
  let consentBody = """
    This app uses the official Tsukuyomi-chan RVC model. To use the RVC \
    feature you must review the official distribution page and the latest \
    terms of use, then agree to them explicitly.
    """
  let consentChecklistTitle = "What you are agreeing to"
  let consentChecklistCredit = """
    When you publish converted audio, you must credit both the original \
    voice and the official model.
    """
  let consentChecklistRights = """
    You are responsible for checking the rights and usage conditions of the \
    original voice yourself.
    """
  let consentChecklistPriority = """
    The latest official terms take precedence over this app’s summary.
    """
  let consentOpenModelPage = "Open the official page"
  let consentOpenTerms = "Open the full official terms"
  let consentAcceptButton = "Agree to the official terms and start"

  func consentRecordNote(revision: String) -> String {
    """
    Pressing the button below records on this Mac that you agreed to the \
    official terms as reviewed on \(revision).
    """
  }

  let creditIncluded = """
    This software includes the RVC model published free of charge for the \
    free-to-use character 「つくよみちゃん」 (Tsukuyomi-chan, © Rei Yumesaki).
    """
  let creditVoice = """
    Voice conversion: つくよみちゃん公式RVCモデル（通常1／CV.夢前黎）
    """
  let creditModelPage = "Official page"
  let creditTerms = "Official terms"
  let creditCompliance = """
    Using the model requires complying with the official RVC model terms of \
    use, and published converted audio must credit both the source of the \
    original voice and the model.
    """
  let creditAccessibility = """
    Voice used: Tsukuyomi-chan official RVC model, Normal 1, CV. Rei \
    Yumesaki. Using the model requires complying with the official terms of \
    use.
    """

  let setupSectionTitle = "Setup steps"
  let setupHint = """
    Hover a step to see the details. Click it to keep that explanation on \
    screen.
    """
  let setupOpenAudioPrivacy = "Open system audio privacy settings"
  let setupOpenFilesPrivacy = "Open file access privacy settings"

  let setupStep1Title = "Allow the permission request"
  let setupStep1Detail = """
    The first time you turn RVC on, macOS asks for the ‘System Audio \
    Recording’ permission. This app only captures the output of the app you \
    select and never uses the microphone. If you still hear nothing after \
    allowing it, quit the app completely and launch it again.
    """
  let setupStep2Title = "Allow file access"
  let setupStep2Detail = """
    The conversion engine reads ‘.rvc_env’ and the model files directly from \
    the project folder. If the project lives in Documents, Desktop, or \
    iCloud Drive, macOS asks for folder access, so please allow it. If you \
    deny it, turning RVC on fails with a runtime-not-found error.
    """
  let setupStep3Title = "Start ChatGPT voice mode (Live)"
  let setupStep3Detail = """
    Start a voice conversation in ChatGPT first so its microphone is active. \
    Pick that same app under ‘App to capture’ here so its output is what \
    gets captured. In ChatGPT’s own settings, the recommended voice is \
    ‘Sol’.
    """
  let setupStep4Title = "Turn on Voice Isolation"
  let setupStep4Detail = """
    With the voice conversation running, open Control Center in the menu bar \
    and choose ‘Mic Mode → Voice Isolation’. It stops the converted voice \
    coming out of your speakers from being picked up by the microphone \
    again, so ChatGPT does not transcribe its own output. You do not need to \
    mute the microphone.
    """
  let setupStep5Title = "Turn RVC on"
  let setupStep5Detail = """
    Once everything is ready, press ‘RVC ON’. While RVC is on, the target \
    app’s direct output is muted and this app plays the converted voice \
    instead. During model loading, processing delays, or a conversion \
    failure, it switches smoothly back to the original audio from the same \
    point in time.
    """

  func setupStepAccessibilityLabel(index: Int, title: String) -> String {
    "Step \(index), \(title)"
  }

  let errorTermsRequired = """
    Please agree to the official RVC model terms of use first.
    """
  let errorSelectTargetApp = "Select an app to capture first."
  let errorUnsupportedSystem = "This app requires macOS 14.2 or later."
  let errorNoAudioProcess = """
    Couldn’t find an audio process for the selected app. Play a sound once \
    in the target app and try again.
    """
  let errorInvalidTap = """
    Couldn’t create the system audio capture for the selected app.
    """
  let errorInvalidAggregateDevice = """
    Couldn’t create the private audio device used for capture.
    """
  let errorInvalidAudioFormat = "The captured audio format can’t be played back."
  let errorBufferAllocation = "Couldn’t allocate the real-time audio buffer."
  let errorProcessorAllocation = "Couldn’t create the RVC output processor."

  let operationStartCapture = "Starting real-time app audio capture"
  let operationCreateTap = "Creating an audio tap for the selected app"
  let operationReadTapFormat = "Reading the audio tap format"
  let operationReadTapUID = "Reading the audio tap identifier"
  let operationCreateAggregateDevice =
    "Creating the virtual device for the audio tap"
  let operationFindAudioProcess = "Looking up the app’s audio process"
  let operationQueryProcessListSize =
    "Checking the Core Audio process list size"
  let operationReadProcessList = "Reading the Core Audio process list"
  let operationReadProcessBundleID = "Reading the audio process bundle ID"

  func coreAudioFailure(
    operation: String,
    code: String,
    status: Int32
  ) -> String {
    "\(operation) failed. (Core Audio \(code), \(status))"
  }
}
