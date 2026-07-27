import SwiftUI

struct SetupStep: Identifiable {
  enum Action {
    case audioPrivacySettings
    case filesPrivacySettings

    var title: String {
      switch self {
      case .audioPrivacySettings:
        return "시스템 오디오 권한 설정 열기"
      case .filesPrivacySettings:
        return "파일 접근 권한 설정 열기"
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
      Label("설정 순서", systemImage: "list.number")
        .font(.headline)
    }
  }

  private var steps: [SetupStep] {
    [
      SetupStep(
        id: 1,
        title: "권한 요청 허가",
        systemImage: "lock.shield",
        detail: """
          RVC를 처음 켤 때 macOS가 ‘시스템 오디오 녹음’ 권한을 요청합니다. \
          이 앱은 선택한 앱의 출력만 캡처하며 마이크는 사용하지 않습니다. \
          허용한 뒤에도 소리가 나오지 않으면 앱을 완전히 종료하고 다시 실행해 주세요.
          """,
        action: .audioPrivacySettings
      ),
      SetupStep(
        id: 2,
        title: "파일 접근 허가",
        systemImage: "folder.badge.person.crop",
        detail: """
          변환 엔진은 프로젝트 폴더의 ‘.rvc_env’와 모델 파일을 직접 읽습니다. \
          프로젝트가 문서·데스크탑·iCloud 폴더 안에 있으면 macOS가 폴더 접근 권한을 \
          요청하므로 허용해 주세요. 거부하면 RVC를 켤 때 런타임을 찾지 못했다는 오류가 납니다.
          """,
        action: .filesPrivacySettings
      ),
      SetupStep(
        id: 3,
        title: "ChatGPT 음성 대화(Live) 켜기",
        systemImage: "bubble.left.and.bubble.right",
        detail: """
          ChatGPT에서 음성 대화를 먼저 시작해 마이크를 활성화합니다. \
          이 앱의 ‘캡처할 앱’에서도 같은 앱을 선택해야 그 앱의 출력이 캡처됩니다. \
          ChatGPT 앱 내 설정의 음성 추천 값은 ‘Sol’입니다.
          """
      ),
      SetupStep(
        id: 4,
        title: "음성 분리 켜기",
        systemImage: "waveform.and.person.filled",
        detail: """
          음성 대화가 켜진 상태에서 메뉴 막대의 제어 센터를 열고 \
          ‘마이크 모드 → 음성 분리’를 선택합니다. 스피커로 나간 변환 음성이 다시 \
          마이크로 들어가 ChatGPT가 자기 목소리를 받아 적는 것을 막아 줍니다. \
          마이크를 음소거하지 않아도 됩니다.
          """
      ),
      SetupStep(
        id: 5,
        title: "RVC 켜기",
        systemImage: "play.circle",
        detail: """
          준비가 끝나면 ‘RVC ON’을 누릅니다. RVC가 켜진 동안 대상 앱의 직접 출력은 \
          음소거되고 이 앱이 변환 음성을 재생합니다. 모델 로딩·처리 지연·변환 실패 시에는 \
          같은 시점의 원음으로 자연스럽게 전환됩니다.
          """
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
    .accessibilityLabel("\(step.id)단계, \(step.title)")
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
        Text("각 단계에 마우스를 올리면 자세한 설명이 표시됩니다. 클릭하면 그 설명이 고정됩니다.")
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
        Button(action.title) {
          perform(action)
        }
        .controlSize(.small)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }
}
