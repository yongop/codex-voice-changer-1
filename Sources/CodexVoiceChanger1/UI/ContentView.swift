import SwiftUI

struct ContentView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Group {
      if model.hasAcceptedTerms {
        mainContent
      } else {
        termsConsent
      }
    }
    .frame(width: 500)
    .fixedSize(horizontal: false, vertical: true)
    .frame(minHeight: 690)
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

  private var mainContent: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack(spacing: 11) {
        Image(systemName: "waveform.badge.mic")
          .font(.system(size: 27, weight: .semibold))
          .foregroundStyle(.tint)
        Text("Codex Voice Changer 1")
          .font(.title2.bold())
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

      SetupGuideView(model: model)

      voiceCredit
        .padding(.top, -10)
    }
    .padding(24)
  }

  private var termsConsent: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(spacing: 11) {
        Image(systemName: "doc.text.magnifyingglass")
          .font(.system(size: 27, weight: .semibold))
          .foregroundStyle(.tint)
        VStack(alignment: .leading, spacing: 2) {
          Text("시작하기 전 이용규약 동의")
            .font(.title2.bold())
          Text("つくよみちゃん公式RVCモデル（通常1）")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Text(
        "이 앱은 츠쿠요미짱 공식 RVC 모델을 사용합니다. RVC 기능을 사용하려면 공식 배포 페이지와 최신 이용규약을 확인하고 명시적으로 동의해야 합니다."
      )
      .font(.body)
      .fixedSize(horizontal: false, vertical: true)

      GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          Label(
            "변환한 음성을 공개할 때 실제 원음과 공식 모델을 함께 밝혀야 합니다.",
            systemImage: "person.wave.2"
          )
          Label(
            "원음의 권리와 이용 조건은 사용자가 별도로 확인해야 합니다.",
            systemImage: "checkmark.shield"
          )
          Label(
            "공식 최신 이용규약이 이 앱의 요약보다 우선합니다.",
            systemImage: "exclamationmark.triangle"
          )
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
      } label: {
        Text("확인할 내용")
          .font(.headline)
      }

      HStack(spacing: 14) {
        Link(
          "공식 배포 페이지 열기",
          destination: TsukuyomiTermsConsent.modelPageURL
        )
        Link(
          "공식 이용규약 전문 열기",
          destination: TsukuyomiTermsConsent.termsURL
        )
      }

      Spacer(minLength: 0)

      Text(
        "아래 버튼을 누르면 \(TsukuyomiTermsConsent.currentRevision) 검토본을 기준으로 공식 이용규약에 동의한 것으로 이 Mac에 기록됩니다."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      Button {
        model.acceptTerms()
      } label: {
        Label(
          "공식 이용규약에 동의하고 시작",
          systemImage: "checkmark.seal.fill"
        )
        .fontWeight(.semibold)
        .frame(maxWidth: .infinity, minHeight: 34)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .keyboardShortcut(.defaultAction)
    }
    .padding(24)
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
          destination: TsukuyomiTermsConsent.modelPageURL
        )
        Link(
          "공식 이용규약",
          destination: TsukuyomiTermsConsent.termsURL
        )
      }
      Text("모델 사용 시 공식 RVC 모델 이용규약을 준수해야 하며, 변환 음성 공개 시 원음 출처와 모델을 함께 표기해야 합니다.")
    }
    .font(.system(size: 10.5))
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
