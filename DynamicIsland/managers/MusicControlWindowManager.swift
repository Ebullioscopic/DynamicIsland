#if os(macOS)
import AppKit
import SwiftUI
import SkyLightWindow
import QuartzCore

struct MusicControlWindowMetrics: Equatable {
    let notchHeight: CGFloat
    let notchWidth: CGFloat
    let rightWingWidth: CGFloat
    let cornerRadius: CGFloat
    let spacing: CGFloat
}

@MainActor
final class MusicControlWindowManager {
    static let shared = MusicControlWindowManager()

    private var window: NSWindow?
    private var hostingView: NSHostingView<MusicControlOverlay>?
    private var hasDelegated = false
    private var lastMetrics: MusicControlWindowMetrics?

    private init() {}

    @discardableResult
    func present(using viewModel: DynamicIslandViewModel, metrics: MusicControlWindowMetrics) -> Bool {
        guard let screen = resolveScreen(from: viewModel) else { return false }
        guard viewModel.effectiveClosedNotchHeight > 0, viewModel.closedNotchSize.width > 0 else {
            hide()
            return false
        }

        let overlay = MusicControlOverlay(
            notchHeight: metrics.notchHeight,
            cornerRadius: metrics.cornerRadius
        )
        let hosting = ensureHostingView(with: overlay)
        let fittingSize = measuredSize(for: hosting)
        hosting.frame = NSRect(origin: .zero, size: fittingSize)

        let window = ensureWindow(on: screen)
        if window.contentView !== hosting {
            window.contentView = hosting
        }

        let targetFrame = frame(for: fittingSize, viewModel: viewModel, screen: screen, metrics: metrics)
        lastMetrics = metrics

        if !hasDelegated {
            SkyLightOperator.shared.delegateWindow(window)
            hasDelegated = true
        }

        if window.alphaValue <= 0.01 {
            let startFrame = initialFrame(for: targetFrame, metrics: metrics)
            window.setFrame(startFrame, display: true)
            window.alphaValue = 0
            window.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(targetFrame, display: true)
                window.animator().alphaValue = 1
            } completionHandler: {
                window.setFrame(targetFrame, display: false)
            }
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(targetFrame, display: true)
            } completionHandler: {
                window.setFrame(targetFrame, display: false)
            }
            window.orderFrontRegardless()
            window.alphaValue = 1
        }

        return true
    }

    @discardableResult
    func refresh(using viewModel: DynamicIslandViewModel, metrics: MusicControlWindowMetrics) -> Bool {
        guard window != nil else {
            return present(using: viewModel, metrics: metrics)
        }

        if let lastMetrics, lastMetrics == metrics {
            return true
        }

        return present(using: viewModel, metrics: metrics)
    }

    func hide(animated: Bool = true, tearDown: Bool = true) {
        guard let window else { return }

        guard animated, window.alphaValue > 0.01 else {
            window.orderOut(nil)
            window.alphaValue = 0
            if tearDown {
                tearDownHostingView()
            }
            return
        }

        let retreatFrame = notchRetreatFrame(from: window.frame)
        let originalFrame = window.frame

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(retreatFrame, display: true)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            window.setFrame(originalFrame, display: false)
            window.orderOut(nil)
            window.alphaValue = 0
            if tearDown {
                self?.tearDownHostingView()
            }
        }
    }

    private func tearDownHostingView() {
        if let window {
            window.contentView = nil
        }
        hostingView = nil
        lastMetrics = nil
    }

    private func ensureHostingView(with overlay: MusicControlOverlay) -> NSHostingView<MusicControlOverlay> {
        if let hostingView {
            hostingView.rootView = overlay
            return hostingView
        }
        let view = NSHostingView(rootView: overlay)
        hostingView = view
        return view
    }

    private func ensureWindow(on screen: NSScreen) -> NSWindow {
        if let window {
            return window
        }

        let window = NSWindow(
            contentRect: NSRect(x: screen.frame.midX, y: screen.frame.midY, width: 240, height: 68),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        window.isMovable = false
        window.alphaValue = 0

        self.window = window
        self.hasDelegated = false
        return window
    }

    private func measuredSize(for hosting: NSHostingView<MusicControlOverlay>) -> CGSize {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    private func resolveScreen(from viewModel: DynamicIslandViewModel) -> NSScreen? {
        if let screenName = viewModel.screen,
           let targetScreen = NSScreen.screens.first(where: { $0.localizedName == screenName }) {
            return targetScreen
        }
        return NSScreen.main
    }

    private func frame(for size: CGSize, viewModel: DynamicIslandViewModel, screen: NSScreen, metrics: MusicControlWindowMetrics) -> NSRect {
        let screenFrame = screen.frame
        let notchOriginX = screenFrame.midX - (metrics.notchWidth / 2)
        let originY = screenFrame.maxY - size.height

        let rightEdge = notchOriginX + metrics.notchWidth + metrics.rightWingWidth
        let rawOriginX = rightEdge + metrics.spacing

        let clampedOriginX = max(screenFrame.minX + 8, min(rawOriginX, screenFrame.maxX - size.width - 8))

        return NSRect(x: clampedOriginX, y: originY, width: size.width, height: size.height)
    }

    private func initialFrame(for targetFrame: NSRect, metrics: MusicControlWindowMetrics) -> NSRect {
        var frame = targetFrame
        let notchRightEdge = targetFrame.minX - metrics.spacing
        frame.origin.x = notchRightEdge - targetFrame.width
        return frame
    }

    private func notchRetreatFrame(from currentFrame: NSRect) -> NSRect {
        guard let metrics = lastMetrics else {
            return currentFrame.offsetBy(dx: -currentFrame.width * 0.75, dy: 0)
        }

        let notchRightEdge = currentFrame.minX - metrics.spacing
        var frame = currentFrame
        frame.origin.x = notchRightEdge - currentFrame.width
        return frame
    }
}

#endif
