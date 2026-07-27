import SwiftUI

struct ContentView: View {
  @ObservedObject var model: AppModel

  private var strings: any AppStringsProviding {
    model.strings
  }

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
      strings.errorAlertTitle,
      isPresented: Binding(
        get: { model.errorText != nil },
        set: { if !$0 { model.errorText = nil } }
      )
    ) {
      Button(strings.okButton, role: .cancel) {
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

        Spacer(minLength: 8)

        languagePicker
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

          Picker(
            strings.captureTargetTitle,
            selection: $model.selectedBundleID
          ) {
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
          .help(strings.refreshRunningApps)
          .disabled(model.isRunning)
        }
        .padding(4)
      } label: {
        Label(
          strings.captureTargetTitle,
          systemImage: "macwindow.on.rectangle"
        )
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
          Text(strings.consentTitle)
            .font(.title2.bold())
          Text("つくよみちゃん公式RVCモデル（通常1）")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 8)

        languagePicker
      }

      Text(strings.consentBody)
        .font(.body)
        .fixedSize(horizontal: false, vertical: true)

      GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          Label(
            strings.consentChecklistCredit,
            systemImage: "person.wave.2"
          )
          Label(
            strings.consentChecklistRights,
            systemImage: "checkmark.shield"
          )
          Label(
            strings.consentChecklistPriority,
            systemImage: "exclamationmark.triangle"
          )
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
      } label: {
        Text(strings.consentChecklistTitle)
          .font(.headline)
      }

      HStack(spacing: 14) {
        Link(
          strings.consentOpenModelPage,
          destination: TsukuyomiTermsConsent.modelPageURL
        )
        Link(
          strings.consentOpenTerms,
          destination: TsukuyomiTermsConsent.termsURL
        )
      }

      Spacer(minLength: 0)

      Text(
        strings.consentRecordNote(
          revision: TsukuyomiTermsConsent.currentRevision
        )
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      Button {
        model.acceptTerms()
      } label: {
        Label(
          strings.consentAcceptButton,
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

  /// The trigger shows only the active language so the fixed 500pt header
  /// stays intact; the longer "follow macOS" wording lives in the menu.
  private var languagePicker: some View {
    Menu {
      Picker(strings.languageMenuTitle, selection: $model.language) {
        ForEach(AppLanguage.allCases) { language in
          Text(language.menuTitle(using: strings))
            .tag(language)
        }
      }
      .pickerStyle(.inline)
      .labelsHidden()
    } label: {
      Label(model.language.resolved.nativeName, systemImage: "globe")
        .font(.callout)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .help(strings.languageMenuTitle)
    .accessibilityLabel(strings.languageMenuTitle)
  }

  private var voiceCredit: some View {
    VStack(alignment: .leading, spacing: 4) {
      Divider()
        .padding(.bottom, 4)

      Text(strings.creditIncluded)
      Text(strings.creditVoice)
        .fontWeight(.medium)
      HStack(spacing: 10) {
        Link(
          strings.creditModelPage,
          destination: TsukuyomiTermsConsent.modelPageURL
        )
        Link(
          strings.creditTerms,
          destination: TsukuyomiTermsConsent.termsURL
        )
      }
      Text(strings.creditCompliance)
    }
    .font(.system(size: 10.5))
    .foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(strings.creditAccessibility)
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
      return strings.activityOff
    case .preparing:
      return strings.activityPreparing
    case .active:
      return strings.activityActive
    case .failed:
      return strings.activityFailed
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
