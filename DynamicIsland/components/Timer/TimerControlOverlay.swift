import SwiftUI

struct TimerControlOverlay: View {
    let notchHeight: CGFloat
    let cornerRadius: CGFloat

    @ObservedObject private var timerManager = TimerManager.shared

    private var pauseIcon: String {
        timerManager.isPaused ? "play.fill" : "pause.fill"
    }

    private var pauseForeground: Color {
        .white
    }

    private var helpText: String {
        timerManager.isPaused ? "Resume" : "Pause"
    }

    private var buttonSize: CGFloat {
        max(notchHeight - 20, 22)
    }

    private var iconSize: CGFloat {
        14
    }

    private var windowCornerRadius: CGFloat {
        max(cornerRadius - 6, 12)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: togglePause) {
                Image(systemName: pauseIcon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .frame(width: buttonSize, height: buttonSize)
                    .foregroundStyle(pauseForeground)
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .help(helpText)

            Button(action: stopTimer) {
                Image(systemName: "stop.fill")
                    .font(.system(size: iconSize, weight: .semibold))
                    .frame(width: buttonSize, height: buttonSize)
                    .foregroundStyle(Color.red)
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .help("Stop")
        }
        .padding(.horizontal, 12)
        .frame(height: notchHeight)
        .frame(minWidth: buttonSize * 2 + 32)
        .background {
            RoundedRectangle(cornerRadius: windowCornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.9))
        }
    .compositingGroup()
        .animation(.smooth(duration: 0.2), value: timerManager.isPaused)
        .animation(.smooth(duration: 0.2), value: timerManager.isFinished)
        .animation(.smooth(duration: 0.2), value: timerManager.isOvertime)
    }

    private func togglePause() {
        if timerManager.isPaused {
            timerManager.resumeTimer()
        } else {
            timerManager.pauseTimer()
        }
    }

    private func stopTimer() {
#if os(macOS)
        TimerControlWindowManager.shared.hide(animated: true)
#endif
        timerManager.stopTimer()
    }
}

#Preview {
    TimerControlOverlay(notchHeight: 34, cornerRadius: 14)
        .padding()
        .background(Color.gray.opacity(0.2))
}
