import SwiftUI

struct ContentView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack(spacing: 11) {
        Image(systemName: "waveform.badge.mic")
          .font(.system(size: 27, weight: .semibold))
          .foregroundStyle(.tint)
        VStack(alignment: .leading, spacing: 2) {
          Text("Codex Voice Changer 1")
            .font(.title2.bold())
          Text("通常1 · RMVPE · +5반음")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      GroupBox {
        HStack(spacing: 12) {
          if let icon = model.selectedApplication?.icon {
            Image(nsImage: icon)
              .resizable()
              .frame(width: 32, height: 32)
          } else {
            Image(systemName: "app.dashed")
              .font(.system(size: 26))
              .frame(width: 32, height: 32)
          }

          Picker("캡처할 앱", selection: $model.selectedBundleID) {
            ForEach(model.applications) { application in
              Text(application.name)
                .tag(application.bundleID)
            }
          }
          .labelsHidden()
          .frame(maxWidth: .infinity)
          .disabled(model.isRunning)

          Button {
            model.refreshApplications()
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .help("실행 중인 앱 새로고침")
          .disabled(model.isRunning)
        }
        .padding(4)
      } label: {
        Label("캡처할 앱", systemImage: "macwindow.on.rectangle")
          .font(.headline)
      }

      VStack(spacing: 10) {
        Button {
          model.toggleRunning()
        } label: {
          HStack {
            Image(systemName: model.isRunning ? "stop.fill" : "play.fill")
            Text(model.isRunning ? "RVC OFF" : "RVC ON")
              .fontWeight(.semibold)
          }
          .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.borderedProminent)
        .tint(model.isRunning ? .red : .accentColor)
        .controlSize(.large)
        .disabled(!model.isRunning && model.selectedApplication == nil)

        activityIndicator
      }

      GroupBox {
        VStack(alignment: .leading, spacing: 9) {
          Text(
            "처음 켤 때 macOS가 ‘시스템 오디오 녹음’ 권한을 요청합니다. 이 앱은 선택한 앱의 출력만 캡처하며 마이크는 사용하지 않습니다."
          )
          Text(
            "권한을 허용한 뒤 소리가 나오지 않으면 앱을 한 번 종료하고 다시 실행해 주세요."
          )
          .foregroundStyle(.secondary)

          Button("시스템 오디오 권한 설정 열기") {
            model.openAudioPrivacySettings()
          }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
      } label: {
        Label("권한 요청 안내", systemImage: "lock.shield")
          .font(.headline)
      }

      Spacer(minLength: 0)

      voiceCredit
    }
    .padding(24)
    .frame(width: 500, height: 555)
    .alert(
      "RVC를 시작하지 못했습니다",
      isPresented: Binding(
        get: { model.errorText != nil },
        set: { if !$0 { model.errorText = nil } }
      )
    ) {
      Button("확인", role: .cancel) {
        model.errorText = nil
      }
    } message: {
      Text(model.errorText ?? "")
    }
  }

  private var voiceCredit: some View {
    VStack(alignment: .leading, spacing: 4) {
      Divider()
        .padding(.bottom, 4)

      Text(
        "이 소프트웨어에는 프리 소재 캐릭터 「つくよみちゃん」(© Rei Yumesaki)이 무료 공개한 RVC 모델이 포함되어 있습니다."
      )
      Text("음성 변환: つくよみちゃん公式RVCモデル（通常1／CV.夢前黎）")
        .fontWeight(.medium)
      HStack(spacing: 10) {
        Link(
          "공식 배포 페이지",
          destination: URL(
            string: "https://tyc.rei-yumesaki.net/work/software/rvc/"
          )!
        )
        Link(
          "공식 이용규약",
          destination: URL(
            string: "https://tyc.rei-yumesaki.net/work/software/rvc/terms/"
          )!
        )
      }
      Text("모델 사용 시 공식 RVC 모델 이용규약을 준수해야 하며, 변환 음성 공개 시 원음 출처와 모델을 함께 표기해야 합니다.")
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "사용 보이스: つくよみちゃん公式RVCモデル 通常1, CV.夢前黎. 모델 사용 시 공식 이용규약을 준수해야 합니다."
    )
  }

  private var activityIndicator: some View {
    HStack(spacing: 8) {
      Circle()
        .fill(activityColor)
        .frame(width: 9, height: 9)
      Text(activityText)
        .font(.callout.weight(.medium))
      Spacer()
    }
    .foregroundStyle(
      model.rvcActivity == .off ? .secondary : .primary
    )
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity, minHeight: 32)
    .background(
      activityColor.opacity(0.1),
      in: RoundedRectangle(cornerRadius: 8, style: .continuous)
    )
    .accessibilityElement(children: .combine)
    .accessibilityLabel(activityText)
  }

  private var activityText: String {
    switch model.rvcActivity {
    case .off:
      return "RVC 엔진 꺼짐"
    case .preparing:
      return "RVC 엔진 가동 준비 중…"
    case .active:
      return "RVC 엔진 가동 중"
    case .failed:
      return "RVC 엔진 오류 · 원음 출력 중"
    }
  }

  private var activityColor: Color {
    switch model.rvcActivity {
    case .off:
      return .secondary
    case .preparing:
      return .orange
    case .active:
      return .green
    case .failed:
      return .red
    }
  }
}
