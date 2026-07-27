import Foundation

struct JapaneseStrings: AppStringsProviding {
  let languageMenuTitle = "言語"
  let languageSystemOption = "システム設定に従う"

  let errorAlertTitle = "RVCを開始できませんでした"
  let okButton = "OK"
  let captureTargetTitle = "キャプチャするアプリ"
  let refreshRunningApps = "実行中のアプリを更新"

  let activityOff = "RVCエンジン停止中"
  let activityPreparing = "RVCエンジンを起動中…"
  let activityActive = "RVCエンジン稼働中"
  let activityFailed = "RVCエンジンエラー・原音を出力中"

  let consentTitle = "開始前に利用規約への同意"
  let consentBody = """
    本アプリはつくよみちゃん公式RVCモデルを使用します。RVC機能を利用するには、公式配布ページと\
    最新の利用規約を確認し、明示的に同意する必要があります。
    """
  let consentChecklistTitle = "確認事項"
  let consentChecklistCredit = "変換した音声を公開する際は、元の音声と公式モデルを併記する必要があります。"
  let consentChecklistRights = "元音声の権利と利用条件は、利用者が別途確認する必要があります。"
  let consentChecklistPriority = "公式の最新利用規約が、本アプリの要約より優先されます。"
  let consentOpenModelPage = "公式配布ページを開く"
  let consentOpenTerms = "公式利用規約の全文を開く"
  let consentAcceptButton = "公式利用規約に同意して開始"

  func consentRecordNote(revision: String) -> String {
    "下のボタンを押すと、\(revision) 時点の版を基準に公式利用規約へ同意したことがこのMacに記録されます。"
  }

  let creditIncluded = """
    本ソフトウェアには、フリー素材キャラクター「つくよみちゃん」（© 夢前黎）が\
    無償公開しているRVCモデルが含まれています。
    """
  let creditVoice = "音声変換: つくよみちゃん公式RVCモデル（通常1／CV.夢前黎）"
  let creditModelPage = "公式配布ページ"
  let creditTerms = "公式利用規約"
  let creditCompliance = """
    モデルの使用にあたっては公式RVCモデル利用規約を遵守し、変換音声を公開する際は\
    原音の出典とモデルを併記する必要があります。
    """
  let creditAccessibility = """
    使用ボイス: つくよみちゃん公式RVCモデル 通常1、CV.夢前黎。\
    モデルの使用時は公式利用規約を遵守する必要があります。
    """

  let setupSectionTitle = "設定手順"
  let setupHint = "各ステップにマウスを重ねると詳しい説明が表示されます。クリックすると説明が固定されます。"
  let setupOpenAudioPrivacy = "システム音声の権限設定を開く"
  let setupOpenFilesPrivacy = "ファイルアクセスの権限設定を開く"

  let setupStep1Title = "権限リクエストを許可"
  let setupStep1Detail = """
    RVCを初めてオンにすると、macOSが「システム音声の録音」権限を要求します。\
    本アプリは選択したアプリの出力のみをキャプチャし、マイクは使用しません。\
    許可しても音が出ない場合は、アプリを完全に終了してから再度起動してください。
    """
  let setupStep2Title = "ファイルアクセスを許可"
  let setupStep2Detail = """
    変換エンジンはプロジェクトフォルダ内の「.rvc_env」とモデルファイルを直接読み込みます。\
    プロジェクトが書類・デスクトップ・iCloudフォルダ内にある場合、macOSがフォルダへの\
    アクセス許可を求めるので許可してください。拒否すると、RVCをオンにしたときに\
    ランタイムが見つからないというエラーになります。
    """
  let setupStep3Title = "ChatGPTの音声会話（Live）を開始"
  let setupStep3Detail = """
    先にChatGPTで音声会話を開始してマイクを有効にします。\
    本アプリの「キャプチャするアプリ」でも同じアプリを選択すると、そのアプリの出力が\
    キャプチャされます。ChatGPTアプリ内の設定では、音声は「Sol」がおすすめです。
    """
  let setupStep4Title = "声を分離をオンにする"
  let setupStep4Detail = """
    音声会話が有効な状態で、メニューバーのコントロールセンターを開き\
    「マイクモード → 声を分離」を選択します。スピーカーから出た変換音声が再びマイクに入り、\
    ChatGPTが自分の声を書き起こしてしまうのを防げます。マイクをミュートする必要はありません。
    """
  let setupStep5Title = "RVCをオンにする"
  let setupStep5Detail = """
    準備ができたら「RVC ON」を押します。RVCがオンの間は対象アプリの直接出力はミュートされ、\
    本アプリが変換音声を再生します。モデルの読み込み中、処理の遅延、変換失敗時には、\
    同じ時点の原音へ自然に切り替わります。
    """

  func setupStepAccessibilityLabel(index: Int, title: String) -> String {
    "ステップ\(index)、\(title)"
  }

  let errorTermsRequired = "先に公式RVCモデルの利用規約に同意してください。"
  let errorSelectTargetApp = "先にキャプチャするアプリを選択してください。"
  let errorUnsupportedSystem = "本アプリはmacOS 14.2以降が必要です。"
  let errorNoAudioProcess = """
    選択したアプリのオーディオプロセスが見つかりませんでした。\
    対象アプリで一度音を再生してから、もう一度お試しください。
    """
  let errorInvalidTap = "選択したアプリのシステム音声キャプチャを作成できませんでした。"
  let errorInvalidAggregateDevice = "キャプチャ用のプライベートオーディオデバイスを作成できませんでした。"
  let errorInvalidAudioFormat = "キャプチャした音声フォーマットは再生できません。"
  let errorBufferAllocation = "リアルタイム音声バッファを確保できませんでした。"
  let errorProcessorAllocation = "RVC出力プロセッサを作成できませんでした。"

  let operationStartCapture = "リアルタイムのアプリ音声キャプチャの開始"
  let operationCreateTap = "選択したアプリのオーディオタップの作成"
  let operationReadTapFormat = "オーディオタップのフォーマットの読み取り"
  let operationReadTapUID = "オーディオタップの識別子の読み取り"
  let operationCreateAggregateDevice = "オーディオタップ用の仮想デバイスの作成"
  let operationFindAudioProcess = "アプリのオーディオプロセスの検索"
  let operationQueryProcessListSize = "Core Audioプロセスリストのサイズの確認"
  let operationReadProcessList = "Core Audioプロセスリストの読み取り"
  let operationReadProcessBundleID = "オーディオプロセスのバンドルIDの読み取り"

  func coreAudioFailure(
    operation: String,
    code: String,
    status: Int32
  ) -> String {
    "\(operation)に失敗しました。(Core Audio \(code), \(status))"
  }
}
