# Codex Voice Changer 1

Real-time voice conversion for a single macOS app's audio, powered by
`つくよみちゃん公式RVCモデル（通常1）`.

**English** · [日本語](#日本語) · [한국어](#한국어)

---

## English

An open-source macOS app that captures **only the output of the app you
select** on an Apple Silicon Mac and converts it in real time. It uses no
microphone and no virtual audio driver, and when conversion lags or fails it
falls back to the original audio from the same point in time.

> [!IMPORTANT]
> The source code is MIT licensed, but the official Tsukuyomi-chan RVC model
> follows its own
> [terms of use](https://tyc.rei-yumesaki.net/work/software/rvc/terms/). The
> model is not included in this repository — setup downloads it from the
> official distributor, and the app makes you review the terms and accept them
> explicitly on first launch before RVC will run.

### Features

- Captures one app's system audio through a macOS Process Tap
- Fixed preset: RVC v2 + RMVPE, `通常1`, pitch `+5` semitones
- Real-time inference on Apple Silicon via PyTorch MPS Float16
- Adaptive jitter buffer sized from measured inference time
- Presentation-time-aligned fallback to the original audio, with short
  crossfades on every switch
- English, Japanese, and Korean UI — follows the macOS language by default,
  switchable from the globe menu
- All audio is processed locally; the app itself makes no network calls

### Requirements

- Apple Silicon Mac, macOS 14.2 or later (Intel is not supported)
- Swift 6.1+ toolchain or Xcode 16.3+, [uv](https://docs.astral.sh/uv/), Git
- ~3 GB of free space and an internet connection for first-time setup
- macOS **System Audio Recording** permission on first run

### Quick start

```sh
./Scripts/setup-runtime.sh   # model, pinned RVC sources, Python 3.11 venv
./Scripts/install-app.sh     # build, sign, install into /Applications
./Scripts/run-app.sh
```

Setup downloads the official model and verifies the pinned RVC sources and the
HuBERT/RMVPE files by SHA-256. It never records terms acceptance on your
behalf; that happens on the app's first-launch screen.

The app reads the project folder's `.rvc_env` at runtime, so moving or deleting
the project breaks it — standalone distribution is not supported yet. If you
cannot write to `/Applications`, set `CVS_APP_INSTALL_DIR` for both the install
and run scripts.

### Usage

Accept the official terms on the first-launch screen, then follow the numbered
`Setup steps` card in the main window. Hover a step for details, click to pin
them.

1. **Allow the permission request** — grant System Audio Recording the first
   time you turn RVC on.
2. **Allow file access** — if the project sits in Documents, Desktop, or iCloud
   Drive, grant folder access so `.rvc_env` and the model can be read.
3. **Start ChatGPT voice mode (Live)** — begin the voice conversation, then
   pick that same app under `App to capture`.
4. **Turn on Voice Isolation** — Control Center → `Mic Mode` →
   `Voice Isolation`. This keeps the converted voice from your speakers from
   being picked up by the microphone again, so the other app does not
   transcribe its own output and you never have to mute the mic. The mic mode
   only appears for apps currently using the microphone.
5. **Turn RVC on** — press `RVC ON`.

While RVC is on, the target app's direct output is muted and this app plays the
converted voice instead. If you allowed the permission but hear nothing, quit
the app completely and launch it again.

### Testing

```sh
swift test
CVS_RUN_RVC_INTEGRATION_TEST=1 \
  swift test --filter RVCStreamingEngineTests/testWorkerIntegrationWhenRequested
./Scripts/audit-public-tree.sh
```

The unit tests run without the model, but `swift test` needs a full Xcode for
`XCTest`; with only the Command Line Tools the app still builds via
`swift build`. The second command exercises the real MPS worker on a
fully set-up Mac, and the audit script re-checks the public tree before
publishing. See [`docs/RELEASING.md`](docs/RELEASING.md) for the distribution
boundary.

### Tsukuyomi-chan credit and conditions

This software uses the RVC model published free of charge for the free-to-use
character `つくよみちゃん` (© Rei Yumesaki). This repository is not an official
or affiliated Tsukuyomi-chan product.

- Model: `つくよみちゃん公式RVCモデル（通常1／CV.夢前黎）`
- [Official model page](https://tyc.rei-yumesaki.net/work/software/rvc/) ·
  [Official terms of use](https://tyc.rei-yumesaki.net/work/software/rvc/terms/)

When you publish converted audio, credit both the original voice and the
official model:

```text
Original voice: my own voice
Voice conversion: つくよみちゃん公式RVCモデル（通常1）
```

If the original voice is someone else's or comes from speech synthesis
software, check that source's rights and conditions separately. The official
prohibitions also apply — campaigning for or against political, religious, or
ideological positions, attacking real people, organizations, or products, and
so on. The latest official terms take precedence over this summary.

### License

The app source is released under the [MIT License](LICENSE). That license does
not cover the official RVC model, the HuBERT/RMVPE weights, or third-party
code; pinned versions and notices are in
[`ThirdPartyLicenses`](ThirdPartyLicenses).

[CONTRIBUTING](CONTRIBUTING.md) · [SECURITY](SECURITY.md) ·
[PRIVACY](PRIVACY.md)

---

## 日本語

Apple Silicon Mac で **選択したアプリの出力音声だけ** をキャプチャし、
リアルタイムで変換するオープンソースの macOS アプリです。マイクも仮想
オーディオドライバも使用せず、変換が遅れたり失敗したりした場合は同じ時点の
原音へ自然に切り替わります。

> [!IMPORTANT]
> ソースコードは MIT ライセンスですが、つくよみちゃん公式 RVC モデルには
> 独自の[利用規約](https://tyc.rei-yumesaki.net/work/software/rvc/terms/)が
> 適用されます。モデルファイルはこのリポジトリに含まれず、セットアップ時に
> 公式配布元からダウンロードします。規約への同意は代行されません。初回起動時に
> 公式ページと規約を確認し、明示的に同意するまで RVC は動作しません。

### 主な機能

- macOS の Process Tap で特定アプリのシステム音声のみをキャプチャ
- 固定プリセット: RVC v2 + RMVPE、`通常1`、ピッチ `+5` 半音
- PyTorch MPS Float16 による Apple Silicon 上のリアルタイム推論
- 実測した推論時間に合わせて調整される適応型ジッタバッファ
- presentation time を揃えた原音フォールバックと、切り替え時の短い
  クロスフェード
- 英語・日本語・韓国語の UI（既定では macOS の言語に追従し、地球儀メニューで
  変更可能）
- 音声処理はすべてローカルで完結し、アプリ自体はネットワークを使用しません

### 必要環境

- Apple Silicon Mac、macOS 14.2 以降（Intel は非対応）
- Swift 6.1 以降のツールチェーンまたは Xcode 16.3 以降、
  [uv](https://docs.astral.sh/uv/)、Git
- 初回セットアップに約 3 GB の空き容量とインターネット接続
- 初回起動時の macOS **システム音声の録音** 権限

### クイックスタート

```sh
./Scripts/setup-runtime.sh   # モデル、固定版 RVC ソース、Python 3.11 仮想環境
./Scripts/install-app.sh     # ビルド・署名して /Applications へインストール
./Scripts/run-app.sh
```

セットアップは公式モデルをダウンロードし、固定版の RVC ソースと
HuBERT/RMVPE ファイルを SHA-256 で検証します。規約への同意は記録しません。
同意はアプリの初回起動画面で行います。

アプリは実行時にプロジェクトフォルダの `.rvc_env` を参照するため、プロジェクトを
移動・削除すると動作しなくなります。単体配布はまだ対応していません。
`/Applications` に書き込めない環境では、インストールと実行の両方で
`CVS_APP_INSTALL_DIR` を指定してください。

### 使い方

初回起動画面で公式規約に同意すると、メインウィンドウに番号付きの
`設定手順` カードが表示されます。各ステップにマウスを重ねると詳細が表示され、
クリックすると固定されます。

1. **権限リクエストを許可** — RVC を初めてオンにするときに求められる
   システム音声の録音権限を許可します。
2. **ファイルアクセスを許可** — プロジェクトが書類・デスクトップ・iCloud
   フォルダ内にある場合、`.rvc_env` とモデルを読み込むためのフォルダ
   アクセスを許可します。
3. **ChatGPT の音声会話（Live）を開始** — 音声会話を始め、本アプリの
   「キャプチャするアプリ」で同じアプリを選択します。
4. **声を分離をオンにする** — コントロールセンター →「マイクモード」→
   「声を分離」。スピーカーから出た変換音声が再びマイクに入るのを防ぐため、
   相手側アプリが自分の声を書き起こすことがなくなり、マイクをミュートする
   必要もありません。マイクモードはマイクを使用中のアプリにのみ表示されます。
5. **RVC をオンにする** — `RVC ON` を押します。

RVC がオンの間は対象アプリの直接出力はミュートされ、本アプリが変換音声を
再生します。権限を許可しても音が出ない場合は、アプリを完全に終了してから
再度起動してください。

### テスト

```sh
swift test
CVS_RUN_RVC_INTEGRATION_TEST=1 \
  swift test --filter RVCStreamingEngineTests/testWorkerIntegrationWhenRequested
./Scripts/audit-public-tree.sh
```

ユニットテストはモデルなしで実行できますが、`swift test` には `XCTest` を含む
完全な Xcode が必要です。Command Line Tools のみの環境でも `swift build` での
ビルドは可能です。2 番目のコマンドはセットアップ済みの Mac で実際の MPS
ワーカーを検証し、監査スクリプトは公開前に公開対象ファイルを再確認します。
配布境界の詳細は [`docs/RELEASING.md`](docs/RELEASING.md) を参照してください。

### つくよみちゃんのクレジットと利用条件

本ソフトウェアは、フリー素材キャラクター `つくよみちゃん`（© 夢前黎）が
無償公開している RVC モデルを使用しています。本リポジトリはつくよみちゃん
プロジェクトの公式・提携製品ではありません。

- モデル: `つくよみちゃん公式RVCモデル（通常1／CV.夢前黎）`
- [公式モデル配布ページ](https://tyc.rei-yumesaki.net/work/software/rvc/) ·
  [公式 RVC モデル利用規約](https://tyc.rei-yumesaki.net/work/software/rvc/terms/)

変換した音声を公開する際は、変換元の音声と公式モデルの両方を明記してください。

```text
元音声: 自分の声
音声変換: つくよみちゃん公式RVCモデル（通常1）
```

他人の音声や音声合成ソフトの出力を使う場合は、その権利と利用条件を別途
確認する必要があります。政治・宗教・思想への賛否を訴える活動、実在の人物・
団体・商品を攻撃する活動など、公式規約の禁止事項も適用されます。本要約より
公式の最新規約が優先されます。

### ライセンス

アプリのソースは [MIT License](LICENSE) で公開しています。このライセンスは
つくよみちゃん公式 RVC モデル、HuBERT/RMVPE の重み、第三者コードの権利には
及びません。固定バージョンと第三者表記は
[`ThirdPartyLicenses`](ThirdPartyLicenses) にあります。

[CONTRIBUTING](CONTRIBUTING.md) · [SECURITY](SECURITY.md) ·
[PRIVACY](PRIVACY.md)

---

## 한국어

Apple Silicon Mac에서 **선택한 앱의 출력 음성만** 캡처해 실시간으로 변환하는
오픈 소스 macOS 앱입니다. 마이크나 가상 오디오 드라이버는 사용하지 않으며,
변환이 늦거나 실패하면 같은 시점의 원음으로 자연스럽게 전환합니다.

> [!IMPORTANT]
> 소스 코드는 MIT 라이선스이지만, 츠쿠요미짱 공식 RVC 모델은 별도의
> [이용규약](https://tyc.rei-yumesaki.net/work/software/rvc/terms/)을 따릅니다.
> 모델 파일은 이 저장소에 포함되지 않으며 설정 시 공식 배포처에서 직접
> 내려받습니다. 이용규약 동의는 대신 기록하지 않으며, 앱을 처음 실행할 때
> 공식 페이지와 규약을 확인하고 명시적으로 동의해야 RVC가 동작합니다.

### 주요 기능

- macOS Process Tap으로 특정 앱의 시스템 오디오만 캡처
- 고정 프리셋: RVC v2 + RMVPE, `通常1`, 피치 `+5` 반음
- PyTorch MPS Float16 기반 Apple Silicon 실시간 추론
- 실측 추론 시간에 맞춰 조정되는 적응형 지터 버퍼
- presentation time을 맞춘 원음 폴백과 전환 시 짧은 크로스페이드
- 영어·일본어·한국어 UI (기본값은 macOS 언어를 따르며 지구본 메뉴에서 변경)
- 모든 오디오 처리를 로컬에서 수행하며 앱 자체는 네트워크를 사용하지 않음

### 요구 사항

- Apple Silicon Mac, macOS 14.2 이상 (Intel 미지원)
- Swift 6.1 이상 도구 모음 또는 Xcode 16.3 이상,
  [uv](https://docs.astral.sh/uv/), Git
- 최초 설정 시 약 3 GB의 여유 공간과 인터넷 연결
- 최초 실행 시 macOS **시스템 오디오 녹음** 권한

### 빠른 시작

```sh
./Scripts/setup-runtime.sh   # 모델, 고정 버전 RVC 소스, Python 3.11 가상환경
./Scripts/install-app.sh     # 빌드·서명 후 /Applications에 설치
./Scripts/run-app.sh
```

설정 스크립트는 공식 모델을 내려받고 고정된 RVC 소스와 HuBERT/RMVPE 파일을
SHA-256으로 검증합니다. 이용규약 동의는 받거나 저장하지 않으며, 동의는 앱의
최초 실행 화면에서 진행합니다.

앱은 실행 중 프로젝트 폴더의 `.rvc_env`를 읽으므로 프로젝트를 옮기거나
지우면 동작하지 않습니다. 독립 실행형 배포는 아직 지원하지 않습니다.
`/Applications`에 쓸 수 없는 환경에서는 설치와 실행 모두에
`CVS_APP_INSTALL_DIR`을 지정하세요.

### 사용법

최초 실행 화면에서 공식 이용규약에 동의하면 메인 화면에 번호가 매겨진
`설정 순서` 카드가 나타납니다. 각 단계에 마우스를 올리면 자세한 설명이,
클릭하면 그 설명이 고정되어 표시됩니다.

1. **권한 요청 허가** — RVC를 처음 켤 때 요청되는 시스템 오디오 녹음 권한을
   허용합니다.
2. **파일 접근 허가** — 프로젝트가 문서·데스크탑·iCloud 폴더 안에 있으면
   `.rvc_env`와 모델 파일을 읽기 위한 폴더 접근 권한을 허용합니다.
3. **ChatGPT 음성 대화(Live) 켜기** — 음성 대화를 시작한 뒤, 이 앱의
   `캡처할 앱`에서 같은 앱을 선택합니다.
4. **음성 분리 켜기** — 제어 센터 → `마이크 모드` → `음성 분리`. 스피커로
   나간 변환 음성이 다시 마이크로 들어가는 것을 막아 주므로, 상대 앱이 자기
   목소리를 받아 적지 않고 마이크를 음소거할 필요도 없습니다. 마이크 모드는
   마이크를 사용 중인 앱에 대해서만 제어 센터에 나타납니다.
5. **RVC 켜기** — `RVC ON`을 누릅니다.

RVC가 켜진 동안 대상 앱의 직접 출력은 음소거되고 이 앱이 변환 음성을
재생합니다. 권한을 허용했는데 소리가 나오지 않으면 앱을 완전히 종료한 뒤
다시 실행하세요.

### 검증

```sh
swift test
CVS_RUN_RVC_INTEGRATION_TEST=1 \
  swift test --filter RVCStreamingEngineTests/testWorkerIntegrationWhenRequested
./Scripts/audit-public-tree.sh
```

단위 테스트는 모델 없이 실행되지만 `swift test`에는 `XCTest`가 포함된 전체
Xcode가 필요합니다. Command Line Tools만 설치된 환경에서도 `swift build`로
빌드는 됩니다. 두 번째 명령은 설정을 마친 Mac에서 실제 MPS 작업자까지
확인하고, 감사 스크립트는 공개 전에 공개 대상 파일을 다시 검사합니다.
배포 경계는 [`docs/RELEASING.md`](docs/RELEASING.md)에 정리되어 있습니다.

### 츠쿠요미짱 크레딧과 사용 조건

이 소프트웨어는 프리 소재 캐릭터 `つくよみちゃん`(© Rei Yumesaki)이 무료
공개한 RVC 모델을 사용합니다. 이 저장소는 츠쿠요미짱 프로젝트의 공식 앱이나
제휴 제품이 아닙니다.

- 모델: `つくよみちゃん公式RVCモデル（通常1／CV.夢前黎）`
- [공식 모델 배포 페이지](https://tyc.rei-yumesaki.net/work/software/rvc/) ·
  [공식 RVC 모델 이용규약](https://tyc.rei-yumesaki.net/work/software/rvc/terms/)

변환한 음성을 공개할 때는 변환 원음과 공식 모델을 모두 밝혀야 합니다.

```text
원음: 본인 음성
음성 변환: つくよみちゃん公式RVCモデル（通常1）
```

다른 사람의 음성이나 음성 합성 소프트웨어 출력을 사용할 때는 그 원음의
권리와 이용 조건을 별도로 확인해야 합니다. 정치·종교·사상에 대한 찬반을
촉구하거나 실재 인물·단체·상품을 공격하는 활동 등 공식 규약의 금지 사항도
적용됩니다. 이 요약보다 공식 최신 규약이 우선합니다.

### 라이선스

앱 소스는 [MIT License](LICENSE)로 공개합니다. 이 라이선스는 츠쿠요미짱 공식
RVC 모델, HuBERT/RMVPE 가중치 또는 제3자 코드의 권리를 대신하지 않습니다.
고정 버전과 제3자 고지는 [`ThirdPartyLicenses`](ThirdPartyLicenses)에
있습니다.

[CONTRIBUTING](CONTRIBUTING.md) · [SECURITY](SECURITY.md) ·
[PRIVACY](PRIVACY.md)
