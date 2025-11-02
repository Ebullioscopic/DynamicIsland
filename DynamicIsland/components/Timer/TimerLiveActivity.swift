//
//  TimerLiveActivity.swift
//  DynamicIsland
//
//  Created by Ebullioscopic on 2025-01-13.
//

import SwiftUI
import Defaults

#if canImport(AppKit)
import AppKit
typealias PlatformFont = NSFont
#elseif canImport(UIKit)
import UIKit
typealias PlatformFont = UIFont
#endif

struct TimerLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var timerManager = TimerManager.shared
    @State private var isHovering: Bool = false
    @State private var showTransientLabel: Bool = false
    @State private var labelHideTask: DispatchWorkItem?
    @State private var isControlWindowVisible: Bool = false
    @Default(.timerShowsCountdown) private var showsCountdown
    @Default(.timerShowsProgress) private var showsProgress
    @Default(.timerShowsLabel) private var showsLabel
    @Default(.timerProgressStyle) private var progressStyle
    @Default(.timerIconColorMode) private var colorMode
    @Default(.timerSolidColor) private var solidColor
    @Default(.timerPresets) private var timerPresets
    @Default(.timerControlWindowEnabled) private var controlWindowEnabled
    
    private var notchContentHeight: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12))
    }

    private var wingPadding: CGFloat { 22 }
    private var ringStrokeWidth: CGFloat { 3 }
    private var transientLabelDuration: TimeInterval { 4 }

    private var ringWrapsIcon: Bool {
        showsRingProgress && showsCountdown
    }

    private var ringOnRight: Bool {
        showsRingProgress && !ringWrapsIcon
    }

    private var iconWidth: CGFloat {
        ringWrapsIcon ? max(notchContentHeight - 6, 28) : max(0, notchContentHeight)
    }

    private var infoContentWidth: CGFloat {
        guard showsInfoSection else { return 0 }
        if shouldDisplayLabel {
            let textWidth = min(max(titleTextWidth, 44), 220)
            return textWidth
        } else {
            return min(max(notchContentHeight * 1.4, 64), 220)
        }
    }

    private var infoWidth: CGFloat {
        guard showsInfoSection else { return 0 }
        return infoContentWidth + 18
    }

    private var leftWingWidth: CGFloat {
        var width = iconWidth + wingPadding
        if showsInfoSection {
            width += 8 + infoWidth
        }
        return width
    }

    private var ringWidth: CGFloat {
        ringOnRight ? 30 : 0
    }

    private var rightWingWidth: CGFloat {
        var width = wingPadding
        if ringOnRight {
            width += ringWidth
        }
        if ringOnRight && showsCountdown {
            width += 8
        }
        if showsCountdown {
            width += countdownWidth
        }
        return width
    }

    private var titleTextWidth: CGFloat {
        measureTextWidth(timerManager.timerName, font: systemFont(size: 12, weight: .medium))
    }

    private var countdownTextWidth: CGFloat {
        measureTextWidth(timerManager.formattedRemainingTime(), font: monospacedDigitFont(size: 13, weight: .semibold))
    }

    private var countdownWidth: CGFloat {
        guard showsCountdown else { return 0 }
        return max(countdownTextWidth + 16, 72)
    }

    private var clampedProgress: Double {
        min(max(timerManager.progress, 0), 1)
    }

    private var glyphColor: Color {
        switch colorMode {
        case .adaptive:
            return activePresetColor ?? timerManager.timerColor
        case .solid:
            return solidColor
        }
    }

    private var showsRingProgress: Bool {
        showsProgress && progressStyle == .ring
    }

    private var showsBarProgress: Bool {
        showsProgress && progressStyle == .bar
    }

    private var shouldDisplayLabel: Bool {
        showsLabel || showTransientLabel
    }

    private var showsInfoSection: Bool {
        shouldDisplayLabel || (showsBarProgress && !showsCountdown)
    }

    private var activePresetColor: Color? {
        guard let presetId = timerManager.activePresetId else { return nil }
        return timerPresets.first { $0.id == presetId }?.color
    }

    private var shouldShowControlWindow: Bool {
        controlWindowEnabled && !shouldDisplayLabel && timerManager.isTimerActive
    }
    
    private func measureTextWidth(_ text: String, font: PlatformFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let width = NSAttributedString(string: text, attributes: attributes).size().width
        return CGFloat(ceil(width))
    }

    private func systemFont(size: CGFloat, weight: PlatformFont.Weight) -> PlatformFont {
        #if canImport(AppKit)
        return NSFont.systemFont(ofSize: size, weight: weight)
        #else
        return UIFont.systemFont(ofSize: size, weight: weight)
        #endif
    }

    private func monospacedDigitFont(size: CGFloat, weight: PlatformFont.Weight) -> PlatformFont {
        #if canImport(AppKit)
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        #else
        return UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        #endif
    }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: leftWingWidth, height: notchContentHeight)
                .background(alignment: .leading) {
                    HStack(spacing: showsInfoSection ? 8 : 0) {
                        iconSection
                        if showsInfoSection {
                            infoSection
                        }
                    }
                    .padding(.leading, wingPadding / 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + (isHovering ? 8 : 0), height: notchContentHeight)

            Color.clear
                .frame(width: rightWingWidth, height: notchContentHeight)
                .background(alignment: .trailing) {
                    HStack(spacing: ringOnRight && showsCountdown ? 8 : 0) {
                        if ringOnRight {
                            ringSection
                        }
                        if showsCountdown {
                            countdownSection
                        }
                    }
                    .padding(.trailing, wingPadding / 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                }
        }
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0), alignment: .center)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.18)) {
                isHovering = hovering
            }
            syncControlWindow(forceRefresh: true)
        }
        .onAppear {
            syncControlWindow(forceRefresh: true)
            if timerManager.isTimerActive && !timerManager.isFinished && !timerManager.isOvertime {
                triggerTransientLabel()
            }
        }
        .onDisappear {
            hideControlWindow()
        }
        .onChange(of: timerManager.isTimerActive) { _, isActive in
            if isActive {
                if !timerManager.isFinished && !timerManager.isOvertime {
                    syncControlWindow(forceRefresh: true)
                    triggerTransientLabel()
                }
            } else {
                hideControlWindow()
                cancelTransientLabel()
                showTransientLabel = false
                isHovering = false
            }
        }
        .onChange(of: timerManager.timerName) { _, _ in
            if timerManager.isTimerActive && !timerManager.isFinished && !timerManager.isOvertime {
                syncControlWindow(forceRefresh: true)
                triggerTransientLabel()
            }
        }
        .onChange(of: timerManager.isFinished) { _, finished in
            if finished {
                cancelTransientLabel()
                withAnimation(.smooth) {
                    showTransientLabel = true
                    isHovering = false
                }
                syncControlWindow()
            }
        }
        .onChange(of: timerManager.isOvertime) { _, overtime in
            if overtime {
                cancelTransientLabel()
                withAnimation(.smooth) {
                    showTransientLabel = true
                    isHovering = false
                }
                syncControlWindow()
            }
        }
        .onChange(of: timerManager.isPaused) { _, _ in
            syncControlWindow(forceRefresh: true)
        }
        .onChange(of: vm.closedNotchSize) { _, _ in
            syncControlWindow(forceRefresh: true)
        }
        .onChange(of: vm.screen) { _, _ in
            syncControlWindow(forceRefresh: true)
        }
        .onChange(of: vm.hideOnClosed) { _, _ in
            syncControlWindow(forceRefresh: true)
        }
        .onChange(of: controlWindowEnabled) { _, _ in
            syncControlWindow(forceRefresh: true)
        }
        .onChange(of: showsLabel) { _, _ in
            syncControlWindow(forceRefresh: true)
        }
        .onChange(of: showTransientLabel) { _, _ in
            syncControlWindow(forceRefresh: true)
        }
        .onChange(of: showsCountdown) { _, _ in
            syncControlWindow(forceRefresh: true)
        }
        .onChange(of: showsProgress) { _, _ in
            syncControlWindow(forceRefresh: true)
        }
        .onChange(of: progressStyle) { _, _ in
            syncControlWindow(forceRefresh: true)
        }
    }
    
    private var iconSection: some View {
        let baseDiameter = ringWrapsIcon ? iconWidth : iconWidth
        let ringDiameter = ringWrapsIcon ? max(min(baseDiameter, notchContentHeight - 2), 22) : iconWidth
        let iconSize = ringWrapsIcon ? max(ringDiameter - 12, 16) : max(18, iconWidth - 6)

        return ZStack {
            if ringWrapsIcon {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: ringStrokeWidth)
                    .frame(width: ringDiameter, height: ringDiameter)

                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(glyphColor, style: StrokeStyle(lineWidth: ringStrokeWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.25), value: clampedProgress)
                    .frame(width: ringDiameter, height: ringDiameter)
            }

            Image(systemName: "timer")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(glyphColor)
                .frame(width: iconSize, height: iconSize)
        }
        .frame(width: ringWrapsIcon ? ringDiameter : iconWidth,
               height: notchContentHeight,
               alignment: .center)
    }
    
    private var infoSection: some View {
    let availableWidth = max(0, infoWidth - 10)
    let safeWidth = max(44, availableWidth - 6)
    let resolvedTextWidth = min(max(titleTextWidth, 44), safeWidth)
        let marqueeLabel = shouldDisplayLabel && (timerManager.isFinished || timerManager.isOvertime || titleTextWidth > availableWidth)
        let showsBarHere = showsBarProgress && !showsCountdown
        let barWidth = shouldDisplayLabel ? resolvedTextWidth : availableWidth

        return Rectangle()
            .fill(.black)
            .frame(width: infoWidth, height: notchContentHeight)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: showsBarHere ? 4 : 0) {
                    if shouldDisplayLabel {
                        if marqueeLabel {
                            MarqueeText(
                                .constant(timerManager.timerName),
                                font: .system(size: 12, weight: .medium),
                                nsFont: .callout,
                                textColor: .white,
                                minDuration: 0.25,
                                frameWidth: resolvedTextWidth
                            )
                        } else {
                            Text(timerManager.timerName)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .foregroundStyle(.white)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                                .frame(width: resolvedTextWidth, alignment: .leading)
                        }
                    }

                    if showsBarHere {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: barWidth, height: 3)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(glyphColor)
                                    .frame(width: barWidth * max(0, CGFloat(clampedProgress)))
                                    .animation(.smooth(duration: 0.25), value: clampedProgress)
                            }
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 6)
            }
            .animation(.smooth, value: timerManager.isFinished)
    }
    
    private var ringSection: some View {
        let diameter = max(min(notchContentHeight - 4, 26), 20)
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: ringStrokeWidth)
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(glyphColor, style: StrokeStyle(lineWidth: ringStrokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.25), value: clampedProgress)
        }
        .frame(width: diameter, height: diameter)
        .frame(width: ringWidth, height: notchContentHeight, alignment: .center)
    }
    
    private var countdownSection: some View {
        let barWidth = max(countdownTextWidth, 1)
        return VStack(spacing: 4) {
            Text(timerManager.formattedRemainingTime())
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(timerManager.isOvertime ? .red : .white)
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.25), value: timerManager.remainingTime)
                .frame(maxWidth: .infinity, alignment: .trailing)
            
            if showsBarProgress {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: barWidth, height: 3)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(glyphColor)
                            .frame(width: barWidth * max(0, CGFloat(clampedProgress)))
                            .animation(.smooth(duration: 0.25), value: clampedProgress)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
     .padding(.trailing, 8)
     .frame(width: countdownWidth,
         height: notchContentHeight, alignment: .center)
    }

    private func triggerTransientLabel() {
        guard !showsLabel else { return }
        cancelTransientLabel()
        withAnimation(.smooth) {
            showTransientLabel = true
        }
        let task = DispatchWorkItem {
            withAnimation(.smooth) {
                showTransientLabel = false
            }
            syncControlWindow(forceRefresh: true)
        }
        labelHideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + transientLabelDuration, execute: task)
    }

    private func cancelTransientLabel() {
        labelHideTask?.cancel()
        labelHideTask = nil
    }

    private func syncControlWindow(forceRefresh: Bool = false) {
#if os(macOS)
        let notchAvailable = vm.effectiveClosedNotchHeight > 0 && vm.closedNotchSize.width > 0
        let targetVisible = shouldShowControlWindow && notchAvailable
        if targetVisible {
            let metrics = currentControlWindowMetrics()
            if !isControlWindowVisible {
                let didPresent = TimerControlWindowManager.shared.present(using: vm, metrics: metrics)
                isControlWindowVisible = didPresent
            } else if forceRefresh {
                let didRefresh = TimerControlWindowManager.shared.refresh(using: vm, metrics: metrics)
                isControlWindowVisible = didRefresh
                if !didRefresh {
                    TimerControlWindowManager.shared.hide()
                }
            }
        } else if isControlWindowVisible {
            TimerControlWindowManager.shared.hide()
            isControlWindowVisible = false
        }
#endif
    }

    private func hideControlWindow() {
#if os(macOS)
        if isControlWindowVisible {
            TimerControlWindowManager.shared.hide()
            isControlWindowVisible = false
        }
#endif
    }

    private func currentControlWindowMetrics() -> TimerControlWindowMetrics {
        TimerControlWindowMetrics(
            notchHeight: max(vm.closedNotchSize.height, vm.effectiveClosedNotchHeight),
            notchWidth: vm.closedNotchSize.width + (isHovering ? 8 : 0),
            rightWingWidth: rightWingWidth,
            cornerRadius: cornerRadiusInsets.closed.bottom,
            spacing: 6
        )
    }
}

#Preview {
    TimerLiveActivity()
        .environmentObject(DynamicIslandViewModel())
        .frame(width: 300, height: 32)
        .background(.black)
        .onAppear {
            TimerManager.shared.startDemoTimer(duration: 300)
        }
}
