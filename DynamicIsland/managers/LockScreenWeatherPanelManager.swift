import AppKit
import SwiftUI
import SkyLightWindow

@MainActor
final class LockScreenWeatherPanelManager {
    static let shared = LockScreenWeatherPanelManager()

    private var window: NSWindow?
    private var hasDelegated = false
    private(set) var latestFrame: NSRect?

    private init() {}

    func show(with snapshot: LockScreenWeatherSnapshot) {
        render(snapshot: snapshot, makeVisible: true)
    }

    func update(with snapshot: LockScreenWeatherSnapshot) {
        render(snapshot: snapshot, makeVisible: false)
    }

    func hide() {
        guard let window else { return }
        window.orderOut(nil)
        window.contentView = nil
        latestFrame = nil
    }

    private func render(snapshot: LockScreenWeatherSnapshot, makeVisible: Bool) {
        guard let screen = NSScreen.main else { return }
        if !makeVisible, window == nil {
            return
        }

        let view = LockScreenWeatherWidget(snapshot: snapshot)
        let hostingView = NSHostingView(rootView: view)
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)

        let targetFrame = frame(for: fittingSize, snapshot: snapshot, on: screen)
        let window = ensureWindow()
        window.setFrame(targetFrame, display: true)
        latestFrame = targetFrame
        window.contentView = hostingView

        if makeVisible {
            window.orderFrontRegardless()
        }
    }

    private func ensureWindow() -> NSWindow {
        if let window {
            return window
        }

        let frame = NSRect(origin: .zero, size: CGSize(width: 110, height: 40))
        let newWindow = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        newWindow.isReleasedWhenClosed = false
        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.hasShadow = false
        newWindow.ignoresMouseEvents = true
        newWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        window = newWindow
        if !hasDelegated {
            SkyLightOperator.shared.delegateWindow(newWindow)
            hasDelegated = true
        }
        return newWindow
    }

    private func frame(for size: CGSize, snapshot: LockScreenWeatherSnapshot, on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let originX = screenFrame.midX - (size.width / 2)
        let verticalOffset = screenFrame.height * 0.15
        let maxY = screenFrame.maxY - size.height - 48
        let baseY = min(maxY, screenFrame.midY + verticalOffset)
        let loweredY = baseY - 36

        let inlineLift: CGFloat = snapshot.widgetStyle == .inline ? 28 : 0
        let adjustedY = loweredY + inlineLift
        let upperClampedY = min(maxY, adjustedY)
        let clampedY = max(screenFrame.minY + 80, upperClampedY)
        return NSRect(x: originX, y: clampedY, width: size.width, height: size.height)
    }
}
