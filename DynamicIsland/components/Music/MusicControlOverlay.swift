import SwiftUI
import Defaults

struct MusicControlOverlay: View {
    let notchHeight: CGFloat
    let cornerRadius: CGFloat

    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.musicSkipBehavior) private var musicSkipBehavior

    private let seekInterval: TimeInterval = 10
    private let skipPressMagnitude: CGFloat = 8

    private var controlsEnabled: Bool {
        !musicManager.isPlayerIdle || musicManager.bundleIdentifier != nil
    }

    private var buttonSide: CGFloat {
        let preferred = notchHeight * 0.94
        let lowerBound = max(30, notchHeight * 0.8)
        let upperBound = max(notchHeight + 2, 32)
        return min(max(preferred, lowerBound), upperBound)
    }

    private var playPauseSide: CGFloat {
        min(buttonSide + 8, notchHeight + 4)
    }

    private var buttonCornerRadius: CGFloat {
        max(cornerRadius - 8, buttonSide * 0.28)
    }

    private var windowCornerRadius: CGFloat {
        max(cornerRadius - 6, 12)
    }

    private var backwardConfig: ButtonConfig {
        switch musicSkipBehavior {
        case .track:
            return ButtonConfig(
                icon: "backward.fill",
                pressEffect: .nudge(-skipPressMagnitude),
                symbolEffect: .replace,
                action: { MusicManager.shared.previousTrack() }
            )
        case .tenSecond:
            return ButtonConfig(
                icon: "gobackward.10",
                pressEffect: .wiggle(.counterClockwise),
                symbolEffect: .wiggle,
                action: { MusicManager.shared.seek(by: -seekInterval) }
            )
        }
    }

    private var forwardConfig: ButtonConfig {
        switch musicSkipBehavior {
        case .track:
            return ButtonConfig(
                icon: "forward.fill",
                pressEffect: .nudge(skipPressMagnitude),
                symbolEffect: .replace,
                action: { MusicManager.shared.nextTrack() }
            )
        case .tenSecond:
            return ButtonConfig(
                icon: "goforward.10",
                pressEffect: .wiggle(.clockwise),
                symbolEffect: .wiggle,
                action: { MusicManager.shared.seek(by: seekInterval) }
            )
        }
    }

    private var playPauseConfig: ButtonConfig {
        ButtonConfig(
            icon: musicManager.isPlaying ? "pause.fill" : "play.fill",
            pressEffect: .none,
            symbolEffect: .replace,
            action: { MusicManager.shared.togglePlay() }
        )
    }

    var body: some View {
        let verticalPadding = max(8, notchHeight * 0.12)

        HStack(spacing: 18) {
            FloatingMediaButton(
                icon: backwardConfig.icon,
                frameSize: CGSize(width: buttonSide, height: buttonSide),
                cornerRadius: buttonCornerRadius,
                foregroundColor: .white.opacity(controlsEnabled ? 0.9 : 0.35),
                pressEffect: backwardConfig.pressEffect,
                symbolEffectStyle: backwardConfig.symbolEffect,
                isEnabled: controlsEnabled,
                action: backwardConfig.action
            )

            FloatingMediaButton(
                icon: playPauseConfig.icon,
                frameSize: CGSize(width: playPauseSide, height: playPauseSide),
                cornerRadius: max(buttonCornerRadius + 2, playPauseSide * 0.32),
                foregroundColor: .white,
                pressEffect: playPauseConfig.pressEffect,
                symbolEffectStyle: playPauseConfig.symbolEffect,
                isEnabled: controlsEnabled,
                action: playPauseConfig.action
            )

            FloatingMediaButton(
                icon: forwardConfig.icon,
                frameSize: CGSize(width: buttonSide, height: buttonSide),
                cornerRadius: buttonCornerRadius,
                foregroundColor: .white.opacity(controlsEnabled ? 0.9 : 0.35),
                pressEffect: forwardConfig.pressEffect,
                symbolEffectStyle: forwardConfig.symbolEffect,
                isEnabled: controlsEnabled,
                action: forwardConfig.action
            )
        }
        .padding(.vertical, verticalPadding)
        .padding(.horizontal, 18)
        .frame(height: notchHeight)
        .frame(minWidth: buttonSide * 3.2)
        .background {
            RoundedRectangle(cornerRadius: windowCornerRadius, style: .continuous)
            .fill(Color.black)
        }
        .compositingGroup()
        .animation(.smooth(duration: 0.2), value: musicManager.isPlaying)
        .animation(.smooth(duration: 0.2), value: musicSkipBehavior)
        .animation(.smooth(duration: 0.2), value: controlsEnabled)
    }

    private struct ButtonConfig {
        let icon: String
        let pressEffect: FloatingMediaButton.PressEffect
        let symbolEffect: FloatingMediaButton.SymbolEffectStyle
        let action: () -> Void
    }
}

private struct FloatingMediaButton: View {
    let icon: String
    let frameSize: CGSize
    let cornerRadius: CGFloat
    let foregroundColor: Color
    let pressEffect: PressEffect
    let symbolEffectStyle: SymbolEffectStyle
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovering = false
    @State private var pressOffset: CGFloat = 0
    @State private var rotationAngle: Double = 0
    @State private var wiggleToken: Int = 0

    var body: some View {
        Button {
            guard isEnabled else { return }
            triggerPressEffect()
            action()
        } label: {
            iconView
                .frame(width: frameSize.width, height: frameSize.height)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isHovering && isEnabled ? Color.white.opacity(0.18) : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
        .offset(x: pressOffset)
        .rotationEffect(.degrees(rotationAngle))
        .disabled(!isEnabled)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) {
                isHovering = hovering
            }
        }
    }

    private var iconView: some View {
        let image = Image(systemName: icon)
            .font(.system(size: min(frameSize.width, frameSize.height) * 0.48, weight: .semibold))
            .foregroundColor(foregroundColor)

        switch symbolEffectStyle {
        case .none:
            return AnyView(image)
        case .replace:
            if #available(macOS 14.0, *) {
                return AnyView(image.contentTransition(.symbolEffect(.replace)))
            } else {
                return AnyView(image)
            }
        case .replaceAndBounce:
            if #available(macOS 14.0, *) {
                return AnyView(
                    image
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: icon)
                )
            } else {
                return AnyView(image)
            }
        case .wiggle:
            if #available(macOS 14.0, *) {
                return AnyView(
                    image.symbolEffect(
                        .wiggle.byLayer,
                        options: .nonRepeating,
                        value: wiggleToken
                    )
                )
            } else {
                return AnyView(image)
            }
        }
    }

    private func triggerPressEffect() {
        switch pressEffect {
        case .none:
            return
        case .nudge(let amount):
            withAnimation(.spring(response: 0.16, dampingFraction: 0.72)) {
                pressOffset = amount
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                    pressOffset = 0
                }
            }
        case .wiggle(let direction):
            guard #available(macOS 14.0, *) else { return }
            wiggleToken += 1
            let angle: Double = direction == .clockwise ? 11 : -11

            withAnimation(.spring(response: 0.18, dampingFraction: 0.52)) {
                rotationAngle = angle
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                    rotationAngle = 0
                }
            }
        }
    }

    enum PressEffect {
        case none
        case nudge(CGFloat)
        case wiggle(WiggleDirection)
    }

    enum SymbolEffectStyle {
        case none
        case replace
        case replaceAndBounce
        case wiggle
    }

    enum WiggleDirection {
        case clockwise
        case counterClockwise
    }
}

#Preview {
    MusicControlOverlay(notchHeight: 34, cornerRadius: 14)
        .padding()
        .background(Color.gray.opacity(0.2))
}
