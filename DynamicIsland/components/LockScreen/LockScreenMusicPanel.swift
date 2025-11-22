//
//  LockScreenMusicPanel.swift
//  DynamicIsland
//
//  Created for lock screen music panel with liquid glass effect
//

import SwiftUI
import Defaults

struct LockScreenMusicPanel: View {
    static let collapsedSize = CGSize(width: 420, height: 180)
    static let expandedSize = CGSize(width: 720, height: 340)

    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject private var routeManager = AudioRouteManager.shared
    @StateObject private var volumeModel = MediaOutputVolumeViewModel()
    @ObservedObject private var animator: LockScreenPanelAnimator
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @State private var isActive = true
    @State private var isExpanded = false
    @State private var isVolumeSliderVisible = false
    @State private var collapseWorkItem: DispatchWorkItem?
    @Default(.lockScreenGlassStyle) var lockScreenGlassStyle
    @Default(.lockScreenShowAppIcon) var showAppIcon
    @Default(.lockScreenPanelShowsBorder) var showPanelBorder
    @Default(.lockScreenPanelUsesBlur) var enableBlur
    @Default(.showMediaOutputControl) var showMediaOutputControl
    @Default(.showShuffleAndRepeat) var showShuffleAndRepeat
    @Default(.musicAuxLeftControl) private var leftAuxControl
    @Default(.musicAuxRightControl) private var rightAuxControl
    @Default(.musicSkipBehavior) private var musicSkipBehavior
    @Default(.enableLyrics) private var enableLyrics

    init(animator: LockScreenPanelAnimator) {
        _animator = ObservedObject(wrappedValue: animator)
    }
    
    private let collapsedPanelCornerRadius: CGFloat = 28
    private let expandedPanelCornerRadius: CGFloat = 52
    private let collapsedAlbumArtCornerRadius: CGFloat = 16
    private let expandedAlbumArtCornerRadius: CGFloat = 60
    private let expandedContentSpacing: CGFloat = 40
    private let collapseTimeout: TimeInterval = 5
    private let collapsedSliderExtraHeight: CGFloat = 72
    private let expandedSliderExtraHeight: CGFloat = 88
    private let collapsedLyricsExtraHeight: CGFloat = 64
    private let expandedLyricsExtraHeight: CGFloat = 96

    private var currentSize: CGSize {
        let base = isExpanded ? Self.expandedSize : Self.collapsedSize
        return CGSize(width: base.width, height: base.height + totalExtraHeight)
    }

    private var panelCornerRadius: CGFloat {
        isExpanded ? expandedPanelCornerRadius : collapsedPanelCornerRadius
    }

    private var usesLiquidGlass: Bool {
        if #available(macOS 26.0, *) {
            return lockScreenGlassStyle == .liquid
        }
        return false
    }
    
    var body: some View {
        if isActive {
            panelContent
        } else {
            Color.clear
                .frame(width: Self.collapsedSize.width, height: Self.collapsedSize.height)
        }
    }
    
    private var panelContent: some View {
        panelCore
            .frame(width: currentSize.width, height: currentSize.height)
            .animation(.spring(response: 0.48, dampingFraction: 0.82, blendDuration: 0.18), value: isExpanded)
            .animation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0.18), value: shouldShowVolumeSlider)
            .onAppear {
                sliderValue = musicManager.elapsedTime
                isActive = true
                logPanelAppearance()
                updatePanelSize(animated: false)
                routeManager.refreshDevices()
            }
            .onDisappear {
                isActive = false
                cancelCollapseTimer()
                isVolumeSliderVisible = false
            }
            .onChange(of: isExpanded) { _, expanded in
                updatePanelSize()
            }
            .onChange(of: showMediaOutputControl) { _, enabled in
                if !enabled {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        isVolumeSliderVisible = false
                    }
                }
                updatePanelSize()
            }
            .onChange(of: enableLyrics) { _, _ in
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    updatePanelSize()
                }
            }
            .scaleEffect(animator.isPresented ? 1 : 0.9, anchor: .center)
            .opacity(animator.isPresented ? 1 : 0)
            .animation(.spring(response: 0.52, dampingFraction: 0.8), value: animator.isPresented)
    }

    @ViewBuilder
    private var panelCore: some View {
        Group {
            if isExpanded {
                expandedLayout
            } else {
                collapsedLayout
            }
        }
        .padding(.horizontal, isExpanded ? 24 : 20)
        .padding(.vertical, isExpanded ? 22 : 16)
        .frame(width: currentSize.width, height: currentSize.height, alignment: .topLeading)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        .overlay {
            if showPanelBorder {
                RoundedRectangle(cornerRadius: panelCornerRadius)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1.4)
            }
        }
        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
    }

    private var collapsedLayout: some View {
        VStack(spacing: 12) {
            collapsedHeader
            progressBar
                .padding(.top, 4)
                .frame(maxWidth: .infinity)
            playbackControls(alignment: .center)
                .padding(.top, 4)
        }
    }

    private var expandedLayout: some View {
        HStack(alignment: .center, spacing: expandedContentSpacing) {
            albumArtButton(size: 230, cornerRadius: expandedAlbumArtCornerRadius)
                .frame(width: 230, height: 230)

            VStack(alignment: .leading, spacing: 20) {
                expandedHeader
                progressBar
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity)
                playbackControls(alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var collapsedHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            albumArtButton(size: 60, cornerRadius: collapsedAlbumArtCornerRadius)

            VStack(alignment: .leading, spacing: 1) {
                Text(musicManager.songTitle.isEmpty ? "No Music Playing" : musicManager.songTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(musicManager.artistName.isEmpty ? "Unknown Artist" : musicManager.artistName)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray)
                    .lineLimit(1)
            }

            Spacer()

            visualizer(width: 20, height: 16)
        }
        .frame(height: 60)
    }

    private var expandedHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(musicManager.songTitle.isEmpty ? "No Music Playing" : musicManager.songTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text(musicManager.artistName.isEmpty ? "Unknown Artist" : musicManager.artistName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.7) : .gray)
                    .lineLimit(2)
            }

            Spacer()

            visualizer(width: 24, height: 20)
        }
    }

    private func albumArtButton(size: CGFloat, cornerRadius: CGFloat) -> some View {
        Button(action: toggleExpanded) {
            ZStack(alignment: .bottomTrailing) {
                albumArtImage(size: size, cornerRadius: cornerRadius)
                if showAppIcon, let icon = lockScreenAppIcon {
                    icon
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: appIconSize, height: appIconSize)
                        .clipShape(RoundedRectangle(cornerRadius: appIconCornerRadius, style: .continuous))
                        .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 4)
                        .offset(x: appIconOffset, y: appIconOffset)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .albumArtFlip(angle: musicManager.flipAngle)
            .frame(width: size, height: size)
            .background(albumArtBackground(cornerRadius: cornerRadius))
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(musicManager.isPlaying ? 1 : 0.4)
        .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
        .animation(.easeInOut(duration: 0.2), value: musicManager.isPlaying)
    }

    @ViewBuilder
    private func visualizer(width: CGFloat, height: CGFloat) -> some View {
        if Defaults[.useMusicVisualizer] {
            Rectangle()
                .fill(Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor).gradient : Color.gray.gradient)
                .mask {
                    AudioSpectrumView(isPlaying: .constant(musicManager.isPlaying))
                        .frame(width: width, height: height)
                }
                .frame(width: width, height: height)
        }
    }

    private func toggleExpanded() {
        let newState = !isExpanded
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            isExpanded = newState
        }

        if newState {
            registerInteraction()
            logPanelAppearance(event: "🔍 Expanded")
        } else {
            logPanelAppearance(event: "⬇️ Collapsed")
            cancelCollapseTimer()
        }
    }

    private func registerInteraction() {
        cancelCollapseTimer()
        guard isExpanded else { return }

        let workItem = DispatchWorkItem {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                isExpanded = false
            }
            logPanelAppearance(event: "⏱️ Auto-collapsed")
        }

        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseTimeout, execute: workItem)
    }

    private func cancelCollapseTimer() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        TimelineView(
            .animation(
                minimumInterval: (!musicManager.isLiveStream && musicManager.playbackRate > 0) ? 0.1 : nil
            )
        ) { timeline in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: Binding(
                    get: { musicManager.songDuration },
                    set: { musicManager.songDuration = $0 }
                ),
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: timeline.date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying,
                isLiveStream: musicManager.isLiveStream,
                onValueChange: { newValue in
                    registerInteraction()
                    musicManager.seek(to: newValue)
                },
                labelLayout: .inline,
                trailingLabel: .remaining,
                restingTrackHeight: 7,
                draggingTrackHeight: 11
            )
        }
        .onAppear {
            sliderValue = musicManager.elapsedTime
        }
        .onChange(of: musicManager.isLiveStream) { _, isLive in
            if isLive {
                dragging = false
                sliderValue = 0
            }
        }
    }

    private var sliderColor: Color {
        switch Defaults[.sliderColor] {
        case .white:
            return .white
        case .albumArt:
            return Color(nsColor: musicManager.avgColor)
        case .accent:
            return .accentColor
        }
    }
    
    // MARK: - Playback Controls
    
    private func playbackControls(alignment: Alignment) -> some View {
        let spacing: CGFloat = isExpanded ? 24 : 20
        let verticalSpacing: CGFloat = (shouldShowVolumeSlider || enableLyrics) ? 14 : 10

        return VStack(spacing: verticalSpacing) {
            controlsRow(alignment: alignment, spacing: spacing)

            if shouldShowVolumeSlider {
                volumeSlider
                    .frame(maxWidth: .infinity, alignment: alignment)
                    .transition(.scale(scale: 0.98, anchor: .top).combined(with: .opacity))
            }

            if enableLyrics {
                lyricsSection(alignment: alignment)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .padding(.top, isExpanded ? 6 : 2)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: shouldShowVolumeSlider)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: enableLyrics)
    }

    private func controlsRow(alignment: Alignment, spacing: CGFloat) -> some View {
        let controls = resolvedAuxControls
        let skipNudge: CGFloat = isExpanded ? 14 : 9
        let seekInterval: TimeInterval = 10

        let backwardConfig: (icon: String, interaction: PanelControlButton.Interaction, symbol: PanelControlButton.SymbolEffectStyle, action: () -> Void)
        let forwardConfig: (icon: String, interaction: PanelControlButton.Interaction, symbol: PanelControlButton.SymbolEffectStyle, action: () -> Void)

        switch musicSkipBehavior {
        case .track:
            backwardConfig = (
                icon: "backward.fill",
                interaction: .nudge(-skipNudge),
                symbol: .replace,
                action: { musicManager.previousTrack() }
            )
            forwardConfig = (
                icon: "forward.fill",
                interaction: .nudge(skipNudge),
                symbol: .replace,
                action: { musicManager.nextTrack() }
            )
        case .tenSecond:
            backwardConfig = (
                icon: "gobackward.10",
                interaction: .wiggle(.counterClockwise),
                symbol: .wiggle,
                action: { musicManager.seek(by: -seekInterval) }
            )
            forwardConfig = (
                icon: "goforward.10",
                interaction: .wiggle(.clockwise),
                symbol: .wiggle,
                action: { musicManager.seek(by: seekInterval) }
            )
        }

        return HStack(spacing: spacing) {
            if let leftControl = controls.left {
                auxButton(for: leftControl)
            }

            controlButton(
                icon: backwardConfig.icon,
                size: 18,
                interaction: backwardConfig.interaction,
                symbolEffect: backwardConfig.symbol,
                action: backwardConfig.action
            )

            playPauseButton

            controlButton(
                icon: forwardConfig.icon,
                size: 18,
                interaction: forwardConfig.interaction,
                symbolEffect: forwardConfig.symbol,
                action: forwardConfig.action
            )

            if let rightControl = controls.right {
                auxButton(for: rightControl)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }
    
    private var playPauseButton: some View {
        let frameSize: CGFloat = isExpanded ? 80 : 54
        let iconName = musicManager.isPlaying ? "pause.fill" : "play.fill"

        return HoverButton(
            icon: iconName,
            iconColor: .white,
            scale: .large,
            pressEffect: nil
        ) {
            registerInteraction()
            musicManager.togglePlay()
        }
        .frame(width: frameSize, height: frameSize)
    }
    
    private func controlButton(
        icon: String,
        size: CGFloat = 18,
        isActive: Bool = false,
        activeColor: Color = .red,
        interaction: PanelControlButton.Interaction = .none,
        symbolEffect: PanelControlButton.SymbolEffectStyle = .replace,
        action: @escaping () -> Void
    ) -> some View {
        let frameSize: CGFloat = isExpanded ? 56 : 32
        let iconSize: CGFloat = isExpanded ? max(size, 24) : size
        let iconColor = isActive ? activeColor : .white.opacity(0.8)
        let backgroundOpacity: Double = isActive ? 0.22 : 0.0

        return PanelControlButton(
            icon: icon,
            frameSize: frameSize,
            iconSize: iconSize,
            iconColor: iconColor,
            backgroundOpacity: backgroundOpacity,
            interaction: interaction,
            symbolEffect: symbolEffect
        ) {
            registerInteraction()
            action()
        }
    }
    
    private var mediaOutputControlButton: some View {
        let frameSize: CGFloat = isExpanded ? 56 : 32
        let iconSize: CGFloat = isExpanded ? 26 : 18

        return PanelControlButton(
            icon: mediaOutputIcon,
            frameSize: frameSize,
            iconSize: iconSize,
            iconColor: shouldShowVolumeSlider ? .accentColor : .white.opacity(0.8),
            backgroundOpacity: shouldShowVolumeSlider ? 0.22 : 0.0,
            interaction: .none,
            symbolEffect: .replace,
            action: toggleVolumeSlider
        )
        .accessibilityLabel("Media output")
    }

    private func lyricsSection(alignment: Alignment) -> some View {
        let line = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        let transition: AnyTransition = .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        )

        return HStack(spacing: 8) {
            if !line.isEmpty {
                Image(systemName: "music.note")
                    .font(.system(size: isExpanded ? 14 : 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .symbolRenderingMode(.monochrome)

                Text(line)
                    .font(.system(size: isExpanded ? 14 : 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 6)
                    .id(line)
                    .transition(transition)
            }
        }
        .padding(.horizontal, isExpanded ? 10 : 8)
        .padding(.top, isExpanded ? 12 : 8)
        .frame(maxWidth: .infinity, alignment: alignment)
        .animation(.smooth(duration: 0.32), value: line)
    }

    private var availableAuxControls: [MusicAuxiliaryControl] {
        MusicAuxiliaryControl.allCases.filter { control in
            control != .mediaOutput || showMediaOutputControl
        }
    }

    private var resolvedAuxControls: (left: MusicAuxiliaryControl?, right: MusicAuxiliaryControl?) {
        guard showShuffleAndRepeat else { return (nil, nil) }

        let options = availableAuxControls
        guard !options.isEmpty else { return (nil, nil) }

        let left = options.contains(leftAuxControl) ? leftAuxControl : options.first!
        var rightCandidate = options.contains(rightAuxControl) ? rightAuxControl : options.first!

        if options.count == 1 {
            return (left, nil)
        }

        if rightCandidate == left, let alternative = options.first(where: { $0 != left }) {
            rightCandidate = alternative
        }

        if rightCandidate == left {
            return (left, nil)
        }

        return (left, rightCandidate)
    }

    @ViewBuilder
    private func auxButton(for control: MusicAuxiliaryControl) -> some View {
        switch control {
        case .shuffle:
            controlButton(icon: "shuffle", isActive: musicManager.isShuffled) {
                musicManager.toggleShuffle()
            }
        case .repeatMode:
            controlButton(icon: repeatIcon, isActive: musicManager.repeatMode != .off) {
                musicManager.toggleRepeat()
            }
        case .mediaOutput:
            mediaOutputControlButton
        case .lyrics:
            controlButton(
                icon: enableLyrics ? "quote.bubble.fill" : "quote.bubble",
                isActive: enableLyrics,
                activeColor: .accentColor
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    enableLyrics.toggle()
                }
            }
        }
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private var mediaOutputIcon: String {
        routeManager.activeDevice?.iconName ?? "speaker.wave.2"
    }

    private var volumeSlider: some View {
        HStack(spacing: 14) {
            Image(systemName: volumeIconName)
                .font(.system(size: isExpanded ? 16 : 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))

            Slider(
                value: Binding(
                    get: { Double(volumeModel.level) },
                    set: { newValue in
                        registerInteraction()
                        volumeModel.setVolume(Float(newValue))
                    }
                ),
                in: 0 ... 1
            )
            .tint(sliderColor)

            Text(volumePercentage)
                .font(.system(size: isExpanded ? 12 : 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: isExpanded ? 16 : 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private var shouldShowVolumeSlider: Bool {
        showMediaOutputControl && isVolumeSliderVisible
    }

    private var sliderExtraHeight: CGFloat {
        sliderHeight(forExpanded: isExpanded, visible: shouldShowVolumeSlider)
    }

    private var lyricsExtraHeight: CGFloat {
        lyricsHeight(forExpanded: isExpanded, enabled: enableLyrics)
    }

    private var totalExtraHeight: CGFloat {
        sliderExtraHeight + lyricsExtraHeight
    }

    private func lyricsHeight(forExpanded expanded: Bool, enabled: Bool) -> CGFloat {
        guard enabled else { return 0 }
        return expanded ? expandedLyricsExtraHeight : collapsedLyricsExtraHeight
    }

    private func panelAdditionalHeight(forExpanded expanded: Bool) -> CGFloat {
        sliderHeight(forExpanded: expanded, visible: shouldShowVolumeSlider) +
        lyricsHeight(forExpanded: expanded, enabled: enableLyrics)
    }

    private func updatePanelSize(animated: Bool = true) {
        LockScreenPanelManager.shared.updatePanelSize(
            expanded: isExpanded,
            additionalHeight: panelAdditionalHeight(forExpanded: isExpanded),
            animated: animated
        )
    }

    private var volumeIconName: String {
        if volumeModel.isMuted || volumeModel.level <= 0.001 {
            return "speaker.slash.fill"
        } else if volumeModel.level < 0.33 {
            return "speaker.wave.1.fill"
        } else if volumeModel.level < 0.66 {
            return "speaker.wave.2.fill"
        }
        return "speaker.wave.3.fill"
    }

    private var volumePercentage: String {
        "\(Int(round(volumeModel.level * 100)))%"
    }

    private func toggleVolumeSlider() {
        guard showMediaOutputControl else {
            isVolumeSliderVisible = false
            return
        }

        registerInteraction()
        let newState = !isVolumeSliderVisible
        if newState {
            routeManager.refreshDevices()
        }

        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            isVolumeSliderVisible = newState
        }

        updatePanelSize()
    }

    private func sliderHeight(forExpanded expanded: Bool, visible: Bool) -> CGFloat {
        guard visible else { return 0 }
        return expanded ? expandedSliderExtraHeight : collapsedSliderExtraHeight
    }

    @ViewBuilder
    private var panelBackground: some View {
        if enableBlur {
            if usesLiquidGlass {
                liquidPanelBackground
            } else {
                frostedPanelBackground
            }
        } else {
            RoundedRectangle(cornerRadius: panelCornerRadius)
                .fill(Color.black.opacity(0.45))
        }
    }

    @ViewBuilder
    private var liquidPanelBackground: some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: panelCornerRadius)
                .glassEffect(
                    .clear
                        //.tint(Color.white.opacity(0.12))
                        .interactive(),
                    in: .rect(cornerRadius: panelCornerRadius)
                )
        }
    }

    private var frostedPanelBackground: some View {
        RoundedRectangle(cornerRadius: panelCornerRadius)
            .fill(.ultraThinMaterial)
    }

    private func albumArtImage(size: CGFloat, cornerRadius: CGFloat) -> some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func albumArtBackground(cornerRadius: CGFloat) -> some View {
        if enableBlur {
            if usesLiquidGlass {
                if #available(macOS 26.0, *) {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .glassEffect(
                            .clear
                                //.tint(Color.white.opacity(0.16))
                                .interactive(),
                            in: .rect(cornerRadius: cornerRadius)
                        )
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                }
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
            }
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.black.opacity(0.35))
        }
    }

    private var lockScreenAppIcon: Image? {
        guard showAppIcon, !musicManager.usingAppIconForArtwork else { return nil }
        let bundleIdentifier = musicManager.bundleIdentifier ?? "com.apple.Music"
        return AppIcon(for: bundleIdentifier)
    }

    private var appIconSize: CGFloat {
        isExpanded ? 58 : 34
    }

    private var appIconCornerRadius: CGFloat {
        isExpanded ? 18 : 10
    }

    private var appIconOffset: CGFloat {
        isExpanded ? 18 : 12
    }

    private func logPanelAppearance(event: String = "✅ View appeared") {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let styleDescriptor = usesLiquidGlass ? "Liquid Glass" : "Frosted"
        print("[\(formatter.string(from: Date()))] LockScreenMusicPanel: \(event) – \(styleDescriptor)")
    }
}

private struct PanelControlButton: View {
    let icon: String
    let frameSize: CGFloat
    let iconSize: CGFloat
    let iconColor: Color
    let backgroundOpacity: Double
    let interaction: Interaction
    let symbolEffect: SymbolEffectStyle
    let action: () -> Void

    @State private var isHovering = false
    @State private var pressOffset: CGFloat = 0
    @State private var rotationAngle: Double = 0
    @State private var wiggleToken: Int = 0

    var body: some View {
        Button(action: {
            triggerPressEffect()
            action()
        }) {
            RoundedRectangle(cornerRadius: frameSize / 2, style: .continuous)
                .fill(backgroundColor)
                .overlay(
                    iconView
                )
        }
        .frame(width: frameSize, height: frameSize)
        .buttonStyle(PlainButtonStyle())
        .offset(x: pressOffset)
        .rotationEffect(.degrees(rotationAngle))
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.24)) {
                isHovering = hovering
            }
        }
    }

    private var backgroundColor: Color {
        let hoveredOpacity = max(backgroundOpacity + 0.08, 0.18)
        let appliedOpacity = isHovering ? hoveredOpacity : backgroundOpacity
        return Color.white.opacity(min(appliedOpacity, 0.32))
    }

    private func triggerPressEffect() {
        switch interaction {
        case .none:
            return
        case .nudge(let amount):
            withAnimation(.spring(response: 0.2, dampingFraction: 0.55)) {
                pressOffset = amount
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    pressOffset = 0
                }
            }
        case .wiggle(let direction):
            guard #available(macOS 14.0, *) else { return }
            wiggleToken += 1
            let angle: Double = direction == .clockwise ? 10 : -10

            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) {
                rotationAngle = angle
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                    rotationAngle = 0
                }
            }
        }
    }

    @ViewBuilder
    private var iconView: some View {
        let base = Image(systemName: icon)
            .font(.system(size: iconSize, weight: .medium))
            .foregroundStyle(iconColor)

        switch symbolEffect {
        case .replace:
            base.contentTransition(.symbolEffect(.replace))
        case .replaceAndBounce:
            if #available(macOS 14.0, *) {
                base
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: icon)
            } else {
                base.contentTransition(.symbolEffect(.replace))
            }
        case .wiggle:
            if #available(macOS 14.0, *) {
                base
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.wiggle.byLayer, options: .nonRepeating, value: wiggleToken)
            } else {
                base.contentTransition(.symbolEffect(.replace))
            }
        }
    }

    enum Interaction {
        case none
        case nudge(CGFloat)
        case wiggle(WiggleDirection)
    }

    enum SymbolEffectStyle {
        case replace
        case replaceAndBounce
        case wiggle
    }

    enum WiggleDirection {
        case clockwise
        case counterClockwise
    }
}
