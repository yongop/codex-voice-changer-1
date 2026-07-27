import SwiftUI

struct SetupStep: Identifiable {
  enum Action {
    case audioPrivacySettings
    case filesPrivacySettings

    func title(using strings: any AppStringsProviding) -> String {
      switch self {
      case .audioPrivacySettings:
        return strings.setupOpenAudioPrivacy
      case .filesPrivacySettings:
        return strings.setupOpenFilesPrivacy
      }
    }
  }

  let id: Int
  let title: String
  let systemImage: String
  let detail: String
  var action: Action?
}

struct SetupGuideView: View {
  @ObservedObject var model: AppModel

  @State private var hoveredStep: Int?
  @State private var pinnedStep: Int?

  private var strings: any AppStringsProviding {
    model.strings
  }

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        VStack(spacing: 1) {
          ForEach(steps) { step in
            row(for: step)
          }
        }
        detailPanel
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(4)
    } label: {
      Label(strings.setupSectionTitle, systemImage: "list.number")
        .font(.headline)
    }
  }

  private var steps: [SetupStep] {
    [
      SetupStep(
        id: 1,
        title: strings.setupStep1Title,
        systemImage: "lock.shield",
        detail: strings.setupStep1Detail,
        action: .audioPrivacySettings
      ),
      SetupStep(
        id: 2,
        title: strings.setupStep2Title,
        systemImage: "folder.badge.person.crop",
        detail: strings.setupStep2Detail,
        action: .filesPrivacySettings
      ),
      SetupStep(
        id: 3,
        title: strings.setupStep3Title,
        systemImage: "bubble.left.and.bubble.right",
        detail: strings.setupStep3Detail
      ),
      SetupStep(
        id: 4,
        title: strings.setupStep4Title,
        systemImage: "waveform.and.person.filled",
        detail: strings.setupStep4Detail
      ),
      SetupStep(
        id: 5,
        title: strings.setupStep5Title,
        systemImage: "play.circle",
        detail: strings.setupStep5Detail
      ),
    ]
  }

  private var activeStep: SetupStep? {
    guard let id = hoveredStep ?? pinnedStep else { return nil }
    return steps.first { $0.id == id }
  }

  private func perform(_ action: SetupStep.Action) {
    switch action {
    case .audioPrivacySettings:
      model.openAudioPrivacySettings()
    case .filesPrivacySettings:
      model.openFilesPrivacySettings()
    }
  }

  private func row(for step: SetupStep) -> some View {
    let isActive = activeStep?.id == step.id

    return Button {
      pinnedStep = pinnedStep == step.id ? nil : step.id
    } label: {
      HStack(spacing: 9) {
        Text("\(step.id)")
          .font(.caption.bold().monospacedDigit())
          .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
          .frame(width: 18, height: 18)
          .background(
            isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
            in: Circle()
          )

        Image(systemName: step.systemImage)
          .font(.caption)
          .foregroundStyle(.tint)
          .frame(width: 15)

        Text(step.title)
          .font(.callout)
          .foregroundStyle(.primary)
          .lineLimit(1)

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 7)
      .padding(.vertical, 5)
      .contentShape(Rectangle())
      .background(
        isActive ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear),
        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
      )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      if hovering {
        hoveredStep = step.id
      } else if hoveredStep == step.id {
        hoveredStep = nil
      }
    }
    .accessibilityLabel(
      strings.setupStepAccessibilityLabel(index: step.id, title: step.title)
    )
    .accessibilityHint(step.detail)
  }

  /// 호버 대상이 바뀌어도 창 높이가 흔들리지 않도록, 모든 단계의 내용을 숨긴
  /// 채로 겹쳐 두어 패널이 항상 가장 큰 단계의 높이를 갖게 한다.
  private var detailPanel: some View {
    ZStack(alignment: .topLeading) {
      ForEach(steps) { step in
        content(for: step)
          .hidden()
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }

      if let step = activeStep {
        content(for: step)
      } else {
        Text(strings.setupHint)
          .font(.caption)
          .foregroundStyle(.tertiary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .padding(9)
    .background(
      .quaternary.opacity(0.5),
      in: RoundedRectangle(cornerRadius: 7, style: .continuous)
    )
    .animation(.easeOut(duration: 0.12), value: activeStep?.id)
  }

  private func content(for step: SetupStep) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(step.detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if let action = step.action {
        Button(action.title(using: strings)) {
          perform(action)
        }
        .controlSize(.small)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }
}
