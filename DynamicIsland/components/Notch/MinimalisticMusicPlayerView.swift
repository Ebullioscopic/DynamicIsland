//
//  MinimalisticMusicPlayerView.swift
//  DynamicIsland
//
//  Created for minimalistic UI mode - Open state music player
//

import SwiftUI
import Defaults

#if canImport(AppKit)
import AppKit
#endif

// Lyrics are shown/hidden only via Defaults[.enableLyrics] in settings. Inline display is used in the player views.

struct MinimalisticMusicPlayerView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    let albumArtNamespace: Namespace.ID
    @Default(.showMediaOutputControl) var showMediaOutputControl
    @ObservedObject private var reminderManager = ReminderLiveActivityManager.shared
    @Default(.enableReminderLiveActivity) private var enableReminderLiveActivity
    @Default(.enableLyrics) private var enableLyrics

    var body: some View {
        VStack(spacing: 0) {
            // Header area with album art (matching DynamicIslandHeader height of 24pt)
            GeometryReader { headerGeo in
                let albumArtWidth: CGFloat = 50
                let spacing: CGFloat = 10
                let visualizerWidth: CGFloat = useMusicVisualizer ? 24 : 0
                let textWidth = max(0, headerGeo.size.width - albumArtWidth - spacing - (useMusicVisualizer ? (visualizerWidth + spacing) : 0))
                HStack(alignment: .center, spacing: spacing) {
                    MinimalisticAlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace)
                        .frame(width: albumArtWidth, height: albumArtWidth)

                    VStack(alignment: .leading, spacing: 1) {
                        if !musicManager.songTitle.isEmpty {
                            MarqueeText(
                                $musicManager.songTitle,
                                font: .system(size: 12, weight: .semibold),
                                nsFont: .subheadline,
                                textColor: .white,
                                frameWidth: textWidth
                            )
                        }

                        Text(musicManager.artistName)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray)
                            .lineLimit(1)

                        // Lyrics shown under the author name, same font size as author
                        if enableLyrics {
                            Text(musicManager.currentLyrics)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.3), value: musicManager.currentLyrics)
                        }
                    }
                    .frame(width: textWidth, alignment: .leading)

                    if useMusicVisualizer {
                        visualizer
                            .frame(width: visualizerWidth)
                    }
                }
            }
            .frame(height: 50)
            
            // Compact progress bar
            progressBar
                .padding(.top, 6)
            
            // Compact playback controls
            playbackControls
                .padding(.top, 4)

            // Lyrics are displayed inline under the artist name (see header area)

            reminderList
        }
        .padding(.horizontal, 12)
        .padding(.top, -15)
        .padding(.bottom, shouldShowReminderList ? ReminderLiveActivityManager.listBottomPadding : ReminderLiveActivityManager.baselineMinimalisticBottomPadding)
        .frame(maxWidth: .infinity)
        .frame(height: calculateDynamicHeight(), alignment: .center)
    .animation(.easeInOut(duration: 0.3), value: musicManager.currentLyrics)
    }

    // MARK: - TypingLyricView

    struct TypingLyricView: View {
        let text: String
        let color: Color
        let id: Int
        let playbackRate: Double
        let isPlaying: Bool
        @State private var displayed: String = ""
        @State private var lastText: String = ""
        @State private var animationTask: Task<Void, Never>?

        var body: some View {
            Text(displayed)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.top, 4)
                .id(id)
                .onChange(of: text) { _, newText in
                    animateTyping(newText)
                }
                .onChange(of: isPlaying) { _, playing in
                    if !playing {
                        animationTask?.cancel()
                    } else if displayed != text {
                        animateTyping(text)
                    }
                }
                .onAppear {
                    animateTyping(text)
                }
                .onDisappear {
                    animationTask?.cancel()
                }
        }

        private func animateTyping(_ newText: String) {
            animationTask?.cancel()
            displayed = ""
            lastText = newText
            let chars = Array(newText)

            animationTask = Task {
                for (i, c) in chars.enumerated() {
                    if Task.isCancelled { return }
                    try? await Task.sleep(for: .milliseconds(Int(30 / max(playbackRate, 0.1))))
                    if Task.isCancelled { return }
                    if lastText == newText {
                        displayed += String(c)
                    }
                }
            }
        }
    }

    private var reminderEntries: [ReminderLiveActivityManager.ReminderEntry] {
        reminderManager.activeWindowReminders
    }

    private var shouldShowReminderList: Bool {
        enableReminderLiveActivity && !reminderEntries.isEmpty
    }

    private var reminderListHeight: CGFloat {
        ReminderLiveActivityManager.additionalHeight(forRowCount: reminderEntries.count)
    }

    private func calculateDynamicHeight() -> CGFloat {
        var height: CGFloat = 50 // Base height for header

        // Add progress bar height
        height += 6 + 4 // progress bar + top padding

        // Add playback controls height
        height += 40 + 2 // controls + top padding

        // Add lyrics height if enabled in settings (reserve space even while loading)
        if Defaults[.enableLyrics] {
            height += 20 + 4 // lyrics + top padding
        }

        // Add reminder list height if showing
        if shouldShowReminderList {
            height += reminderListHeight + ReminderLiveActivityManager.listTopPadding
        }

        // Add padding
        height += 15 // top padding
        height += shouldShowReminderList ? ReminderLiveActivityManager.listBottomPadding : ReminderLiveActivityManager.baselineMinimalisticBottomPadding

        return height
    }

    private var reminderList: some View {
        MinimalisticReminderEventListView(reminders: reminderEntries)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: reminderListHeight, alignment: .top)
            .opacity(shouldShowReminderList ? 1 : 0)
            .animation(.easeInOut(duration: 0.18), value: shouldShowReminderList)
            .environmentObject(vm)
    }
    

private struct MinimalisticReminderEventListView: View {
    let reminders: [ReminderLiveActivityManager.ReminderEntry]

    private let textFont = Font.system(size: 13, weight: .semibold)
    private let separatorSpacing: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: ReminderLiveActivityManager.listRowSpacing) {
            ForEach(reminders) { entry in
                MinimalisticReminderEventRow(entry: entry, textFont: textFont, separatorSpacing: separatorSpacing)
            }
        }
        .padding(.top, ReminderLiveActivityManager.listTopPadding)
    }
}

private struct MinimalisticReminderEventRow: View {
    let entry: ReminderLiveActivityManager.ReminderEntry
    let textFont: Font
    let separatorSpacing: CGFloat

    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var didCopyLink = false
    @State private var copyResetToken: UUID?
    @State private var isDetailsPopoverPresented = false
    @State private var isHoveringDetailsPopover = false

    private let indicatorHeight: CGFloat = 20

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(spacing: separatorSpacing) {
            RoundedRectangle(cornerRadius: 3)
                .fill(eventColor)
                .frame(width: 8, height: indicatorHeight)

            HStack(spacing: 6) {
                Text(entry.event.title)
                    .font(textFont)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)

                if let timeText {
                    Text(timeText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            HStack(spacing: separatorSpacing) {
                if let url = linkURL {
                    Button {
                        copyToClipboard(url: url)
                        triggerCopyFeedback()
                    } label: {
                        Image(systemName: didCopyLink ? "checkmark.circle.fill" : "link")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(didCopyLink ? Color.green : Color.white.opacity(0.85))
                            .symbolRenderingMode(.monochrome)
                            .animation(.easeInOut(duration: 0.2), value: didCopyLink)
                    }
                    .buttonStyle(.plain)
                    .help("Copy event link")
                }

                if hasDetails {
                    Button {
                        isDetailsPopoverPresented.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isDetailsPopoverPresented, arrowEdge: .top) {
                        MinimalisticReminderDetailsView(
                            entry: entry,
                            linkURL: linkURL,
                            onHoverChanged: { hovering in
                                isHoveringDetailsPopover = hovering
                                updatePopoverActivity()
                            }
                        )
                        .onDisappear {
                            isHoveringDetailsPopover = false
                            updatePopoverActivity()
                        }
                    }
                    .onChange(of: isDetailsPopoverPresented) { _, presented in
                        if !presented {
                            isHoveringDetailsPopover = false
                            updatePopoverActivity()
                        }
                    }
                }
            }
        }
        .frame(height: ReminderLiveActivityManager.listRowHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            openInCalendar()
        }
        .onDisappear {
            copyResetToken = nil
            didCopyLink = false
            vm.isReminderPopoverActive = false
        }
    }

    private var eventColor: Color {
        Color(nsColor: entry.event.calendar.color).ensureMinimumBrightness(factor: 0.7)
    }

    private var hasDetails: Bool {
        let location = entry.event.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let notes = entry.event.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !location.isEmpty || !notes.isEmpty
    }

    private var linkURL: URL? {
        entry.event.url ?? entry.event.calendarAppURL()
    }

    private var timeText: String? {
        Self.timeFormatter.string(from: entry.event.start)
    }

    private func updatePopoverActivity() {
        vm.isReminderPopoverActive = isDetailsPopoverPresented && isHoveringDetailsPopover
    }

    private func triggerCopyFeedback() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
            didCopyLink = true
        }

        let token = UUID()
        copyResetToken = token

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [token] in
            guard copyResetToken == token else { return }

            withAnimation(.easeInOut(duration: 0.2)) {
                didCopyLink = false
            }

            if copyResetToken == token {
                copyResetToken = nil
            }
        }
    }

    private func copyToClipboard(url: URL) {
#if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
#endif
    }

    private func openInCalendar() {
#if canImport(AppKit)
        guard let url = linkURL else { return }
        NSWorkspace.shared.open(url)
#endif
    }
}

private struct MinimalisticReminderDetailsView: View {
    let entry: ReminderLiveActivityManager.ReminderEntry
    let linkURL: URL?
    var onHoverChanged: (Bool) -> Void = { _ in }

    private let detailFont = Font.system(size: 13, weight: .regular)
    private let smallLabelFont = Font.system(size: 12, weight: .semibold)
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entry.event.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 6) {
                if let timeRange = timeRangeText {
                    detailRow(icon: "clock", label: "Time", value: timeRange)
                }

                if let location = entry.event.location, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    detailRow(icon: "mappin.and.ellipse", label: "Location", value: location)
                }

                if let notes = entry.event.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    detailRow(icon: "note.text", label: "Notes", value: notes)
                }
            }

            if let url = linkURL {
                Button {
                    open(url: url)
                } label: {
                    Label("Open in Calendar", systemImage: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.link)
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(16)
        .frame(minWidth: 220)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
        .onHover { hovering in
            onHoverChanged(hovering)
        }
        .onDisappear {
            onHoverChanged(false)
        }
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(smallLabelFont)
                .foregroundStyle(Color.white.opacity(0.8))
            Text(value)
                .font(detailFont)
                .foregroundStyle(Color.white)
        }
    }

    private var timeRangeText: String? {
        let startText = Self.timeFormatter.string(from: entry.event.start)
        let endText = Self.timeFormatter.string(from: entry.event.end)
        return startText == endText ? startText : "\(startText) – \(endText)"
    }

    private func open(url: URL) {
#if canImport(AppKit)
        NSWorkspace.shared.open(url)
#endif
    }
}
    // MARK: - Visualizer
    
    @Default(.useMusicVisualizer) var useMusicVisualizer
    
    private var visualizer: some View {
        Rectangle()
            .fill(Defaults[.coloredSpectrogram] ? Color(nsColor: MusicManager.shared.avgColor).gradient : Color.gray.gradient)
            .mask {
                AudioSpectrumView(isPlaying: .constant(MusicManager.shared.isPlaying))
                    .frame(width: 20, height: 16)
            }
            .frame(width: 20, height: 16)
            .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
    }
    
    // MARK: - Progress Bar (Full Width)
    
    @ObservedObject var musicManager = MusicManager.shared
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    
    private var progressBar: some View {
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.1 : nil)) { timeline in
            if musicManager.isLiveStream {
                HStack(spacing: 8) {
                    Spacer()
                        .frame(width: 42)
                    LiveStreamProgressIndicator(tint: sliderColor)
                        .frame(maxWidth: .infinity, minHeight: 6, maxHeight: 6)
                    Spacer()
                        .frame(width: 48)
                }
                .allowsHitTesting(false)
            } else {
                let currentElapsed = currentSliderValue(timeline.date)

                HStack(spacing: 8) {
                    Text(formatTime(dragging ? sliderValue : currentElapsed))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 42, alignment: .leading)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(sliderColor)
                                .frame(width: max(0, geometry.size.width * (currentSliderValue(timeline.date) / max(musicManager.songDuration, 1))), height: 6)
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    dragging = true
                                    let newValue = min(max(0, Double(value.location.x / geometry.size.width) * musicManager.songDuration), musicManager.songDuration)
                                    sliderValue = newValue
                                    lastDragged = Date()
                                }
                                .onEnded { _ in
                                    musicManager.seek(to: sliderValue)
                                    dragging = false
                                }
                        )
                    }
                    .frame(height: 6)

                    Text("-\(formatTime(musicManager.songDuration - (dragging ? sliderValue : currentElapsed)))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
        .onAppear {
            sliderValue = musicManager.elapsedTime
        }
    }
    
    private func currentSliderValue(_ date: Date) -> Double {
        if dragging {
            return sliderValue
        }
        
        // Update slider value based on playback
        if musicManager.isPlaying {
            let timeSinceLastUpdate = date.timeIntervalSince(musicManager.timestampDate)
            let estimatedElapsed = musicManager.elapsedTime + (timeSinceLastUpdate * musicManager.playbackRate)
            return min(estimatedElapsed, musicManager.songDuration)
        }
        
        return musicManager.elapsedTime
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
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Playback Controls (Larger)
    
    private var playbackControls: some View {
        HStack(spacing: 16) {
            if Defaults[.showShuffleAndRepeat] {
                controlButton(icon: "shuffle", isActive: musicManager.isShuffled) {
                    Task { await musicManager.toggleShuffle() }
                }
            }

            controlButton(icon: "backward.fill", size: 18) {
                Task { await musicManager.previousTrack() }
            }

            playPauseButton

            controlButton(icon: "forward.fill", size: 18) {
                Task { await musicManager.nextTrack() }
            }

            // (lyrics toggle removed from UI; controlled via Settings -> Media -> Enable Lyrics)

            if Defaults[.showShuffleAndRepeat] {
                if showMediaOutputControl {
                    MinimalisticMediaOutputButton()
                } else {
                    controlButton(icon: repeatIcon, isActive: musicManager.repeatMode != .off) {
                        Task { await musicManager.toggleRepeat() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }
    
    private var playPauseButton: some View {
        MinimalisticSquircircleButton(
            icon: musicManager.isPlaying ? "pause.fill" : "play.fill",
            fontSize: 24,
            fontWeight: .semibold,
            frameSize: CGSize(width: 54, height: 54),
            cornerRadius: 20,
            foregroundColor: .white,
            action: {
                Task { await musicManager.togglePlay() }
            }
        )
    }
    
    private func controlButton(icon: String, size: CGFloat = 18, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        MinimalisticSquircircleButton(
            icon: icon,
            fontSize: size,
            fontWeight: .medium,
            frameSize: CGSize(width: 40, height: 40),
            cornerRadius: 16,
            foregroundColor: isActive ? .red : .white.opacity(0.85),
            action: action
        )
    }
    private struct MinimalisticMediaOutputButton: View {
        @ObservedObject private var routeManager = AudioRouteManager.shared
        @StateObject private var volumeModel = MediaOutputVolumeViewModel()
        @EnvironmentObject private var vm: DynamicIslandViewModel
        @State private var isPopoverPresented = false
        @State private var isHoveringPopover = false

        var body: some View {
            MinimalisticSquircircleButton(
                icon: routeManager.activeDevice?.iconName ?? "speaker.wave.2",
                fontSize: 18,
                fontWeight: .medium,
                frameSize: CGSize(width: 40, height: 40),
                cornerRadius: 16,
                foregroundColor: .white.opacity(0.85)
            ) {
                isPopoverPresented.toggle()
                if isPopoverPresented {
                    routeManager.refreshDevices()
                }
            }
            .accessibilityLabel("Media output")
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                MediaOutputSelectorPopover(
                    routeManager: routeManager,
                    volumeModel: volumeModel,
                    onHoverChanged: { hovering in
                        isHoveringPopover = hovering
                        updateActivity()
                    }
                ) {
                    isPopoverPresented = false
                    isHoveringPopover = false
                    updateActivity()
                }
            }
            .onChange(of: isPopoverPresented) { _, presented in
                if !presented {
                    isHoveringPopover = false
                }
                updateActivity()
            }
            .onAppear {
                routeManager.refreshDevices()
            }
            .onDisappear {
                vm.isMediaOutputPopoverActive = false
            }
        }

        private func updateActivity() {
            vm.isMediaOutputPopoverActive = isPopoverPresented && isHoveringPopover
        }
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

// MARK: - Minimalistic Album Art

struct MinimalisticAlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: DynamicIslandViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if Defaults[.lightingEffect] {
                albumArtBackground
            }
            albumArtButton
        }
    }
    
    private var albumArtBackground: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background(
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            )
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(x: 1.3, y: 1.4)
            .rotationEffect(.degrees(92))
            .blur(radius: 35)
            .opacity(min(0.6, 1 - max(musicManager.albumArt.getBrightness(), 0.3)))
    }
    
    private var albumArtButton: some View {
        Button {
            musicManager.openMusicApp()
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .background(
                    Image(nsImage: musicManager.albumArt)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                )
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .albumArtFlip(angle: musicManager.flipAngle)
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(musicManager.isPlaying ? 1 : 0.4)
        .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
    }
}

// MARK: - Hover-highlighted control button

private struct MinimalisticSquircircleButton: View {
    let icon: String
    let fontSize: CGFloat
    let fontWeight: Font.Weight
    let frameSize: CGSize
    let cornerRadius: CGFloat
    let foregroundColor: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundColor(foregroundColor)
                .frame(width: frameSize.width, height: frameSize.height)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isHovering ? Color.white.opacity(0.18) : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) {
                isHovering = hovering
            }
        }
    }
}
