import SwiftUI

/// First-run setup: a fixed rail of lamps down the left, and a stage on the right that
/// changes per step.
///
/// The rail is the only navigation. There is no Next or Back — a lamp lighting *is* the
/// confirmation that a step is done, which is how equipment reports its own state and
/// happens to be exactly what a permission wizard needs.
struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    let controller: DictationController

    @State private var permissions = PermissionMonitor.shared

    var body: some View {
        ZStack {
            DS.Color.chassis.ignoresSafeArea()

            ZStack {
                BrushedPanel()

                HStack(spacing: 0) {
                    SetupRail(current: model.step, permissions: permissions)
                        .frame(width: Self.railWidth)

                    Rectangle()
                        .fill(DS.Color.seam)
                        .frame(width: DS.Border.seam)

                    stage
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(DS.Space.panel)
                }
            }
            .padding(DS.Space.roomy)
        }
        .frame(minWidth: 720, minHeight: 520)
        // Grants advance the flow. Driven from here rather than from a callback on
        // PermissionMonitor so the app delegate can watch the same transition for its own
        // reason (arming the event tap) without the two overwriting each other.
        .onChange(of: permissions.accessibility) { _, granted in
            guard granted else { return }
            withAnimation(DS.Motion.panel) { model.accessibilityDidLand() }
        }
        .onChange(of: permissions.microphone) { _, granted in
            guard granted, model.step == .microphone else { return }
            withAnimation(DS.Motion.panel) { model.advance() }
        }
    }

    private static let railWidth: CGFloat = 208

    @ViewBuilder
    private var stage: some View {
        VStack(alignment: .leading, spacing: DS.Space.roomy) {
            HStack {
                Silkscreen(text: "Step \(model.step.rawValue + 1) of \(OnboardingModel.Step.allCases.count)",
                           color: DS.Color.inkSecondary)
                Spacer()
                Screw()
            }

            switch model.step {
            case .welcome: WelcomeStep(model: model)
            case .accessibility: AccessibilityStep(model: model, permissions: permissions)
            case .microphone: MicrophoneStep(model: model)
            case .key: KeyStep(model: model, controller: controller)
            case .tryIt: TryItStep(model: model, controller: controller)
            case .done: DoneStep(model: model)
            }
        }
    }
}

// MARK: - Rail

/// The step list: a lamp per step, lit as you clear it.
private struct SetupRail: View {
    let current: OnboardingModel.Step
    let permissions: PermissionMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.wide) {
            VStack(alignment: .leading, spacing: DS.Space.hair) {
                Silkscreen(text: "Blurt", large: true)
                Silkscreen(text: "Push-to-talk dictation", color: DS.Color.inkSecondary)
            }

            Rectangle()
                .fill(DS.Color.seam)
                .frame(height: DS.Border.seam)
                .opacity(0.5)

            VStack(alignment: .leading, spacing: DS.Space.hair) {
                Silkscreen(text: "Setup", color: DS.Color.inkSecondary)
                    .padding(.horizontal, DS.Space.snug)
                    .padding(.bottom, DS.Space.tight)

                ForEach(OnboardingModel.Step.allCases, id: \.self) { step in
                    row(for: step)
                }
            }

            Spacer()

            HStack(alignment: .bottom) {
                Screw()
                Spacer()
                Vents()
            }
        }
        .padding(DS.Space.roomy)
    }

    private func row(for step: OnboardingModel.Step) -> some View {
        let isCurrent = step == current
        return HStack(spacing: DS.Space.snug) {
            Lamp(color: DS.Color.statusLamp, isLit: isDone(step))
            Silkscreen(text: step.title, color: isCurrent ? DS.Color.ink : DS.Color.silkscreen)
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Space.snug - DS.Space.hair)
        .padding(.horizontal, DS.Space.snug)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: DS.Radius.chip)
                    .fill(DS.Color.selection)
                    .strokeBorder(DS.Color.selectionEdge, lineWidth: DS.Border.hairline)
            }
        }
    }

    /// A step's lamp lights when it's genuinely behind you. For the two permission steps
    /// that means the grant is actually held — walking past one with Skip leaves it dark,
    /// which is the truth and is what the deck's banner is about.
    private func isDone(_ step: OnboardingModel.Step) -> Bool {
        switch step {
        case .accessibility: permissions.accessibility
        case .microphone: permissions.microphone
        default: step.rawValue < current.rawValue
        }
    }
}
