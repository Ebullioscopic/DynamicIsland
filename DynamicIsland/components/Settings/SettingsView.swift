//
//  SettingsView.swift
//  DynamicIsland
//
//  Created by Richard Kunkli on 07/08/2024.
// Modified by Hariharan Mudaliar

import AVFoundation
import Defaults
import EventKit
import KeyboardShortcuts
import LaunchAtLogin
import LottieUI
import Sparkle
import SwiftUI
import SwiftUIIntrospect
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject var extensionManager = DynamicIslandExtensionManager()
    @StateObject private var calendarManager = CalendarManager()
    
    @State private var selectedTab = "General"
    
    let updaterController: SPUStandardUpdaterController?
    
    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: "General") {
                    Label("General", systemImage: "gear")
                }
                NavigationLink(value: "Appearance") {
                    Label("Appearance", systemImage: "eye")
                }
                NavigationLink(value: "Media") {
                    Label("Media", systemImage: "play.laptopcomputer")
                }
                NavigationLink(value: "Timer") {
                    Label("Timer", systemImage: "timer")
                }
                NavigationLink(value: "Calendar") {
                    Label("Calendar", systemImage: "calendar")
                }
                if extensionManager.installedExtensions
                    .contains(where: { $0.bundleIdentifier == hudExtension }) {
                    NavigationLink(value: "HUD") {
                        Label("HUDs", systemImage: "dial.medium.fill")
                    }
                }
                NavigationLink(value: "Battery") {
                    Label("Battery", systemImage: "battery.100.bolt")
                }
                if extensionManager.installedExtensions
                    .contains(where: { $0.bundleIdentifier == downloadManagerExtension }) {
                    NavigationLink(value: "Downloads") {
                        Label("Downloads", systemImage: "square.and.arrow.down")
                    }
                }
                NavigationLink(value: "Shelf") {
                    Label("Shelf", systemImage: "books.vertical")
                }
                NavigationLink(value: "Stats") {
                    Label("Stats", systemImage: "chart.line.uptrend.xyaxis")
                }
                NavigationLink(value: "Clipboard") {
                    Label("Clipboard", systemImage: "doc.on.clipboard")
                }
                NavigationLink(value: "Shortcuts") {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                NavigationLink(value: "Extensions") {
                    Label("Extensions", systemImage: "puzzlepiece.extension")
                }
                NavigationLink(value: "About") {
                    Label("About", systemImage: "info.circle")
                }
            }
            .listStyle(SidebarListStyle())
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            Group {
                switch selectedTab {
                case "General":
                    GeneralSettings()
                case "Appearance":
                    Appearance()
                case "Media":
                    Media()
                case "Timer":
                    TimerSettings()
                case "Calendar":
                    CalendarSettings()
                case "HUD":
                    HUD()
                case "Battery":
                    Charge()
                case "Downloads":
                    Downloads()
                case "Shelf":
                    Shelf()
                case "Stats":
                    Stats()
                case "Clipboard":
                    ClipboardSettings()
                case "Shortcuts":
                    Shortcuts()
                case "Extensions":
                    Extensions()
                case "About":
                    if let controller = updaterController {
                        About(updaterController: controller)
                    } else {
                        // Fallback with a default controller
                        About(updaterController: SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil))
                    }
                default:
                    GeneralSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            Button("") {} // Empty label, does nothing
                .controlSize(.extraLarge)
                .opacity(0) // Invisible, but reserves space for a consistent look between tabs
                .disabled(true)
        }
        .environmentObject(extensionManager)
        .environmentObject(calendarManager)
        .formStyle(.grouped)
        .frame(width: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct GeneralSettings: View {
    @State private var screens: [String] = NSScreen.screens.compactMap { $0.localizedName }
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared

    @Default(.mirrorShape) var mirrorShape
    @Default(.showEmojis) var showEmojis
    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.notchHeight) var notchHeight
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay
    @Default(.enableGestures) var enableGestures
    @Default(.openNotchOnHover) var openNotchOnHover
    @Default(.alwaysHideInFullscreen) var alwaysHideInFullscreen
    
    var body: some View {
        Form {
            Section {
                Defaults.Toggle("Menubar icon", key: .menubarIcon)
                LaunchAtLogin.Toggle("Launch at login")
                Defaults.Toggle(key: .showOnAllDisplays) {
                    Text("Show on all displays")
                }
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                }
                Picker("Show on a specific display", selection: $coordinator.preferredScreen) {
                    ForEach(screens, id: \.self) { screen in
                        Text(screen)
                    }
                }
                .onChange(of: NSScreen.screens) {
                    screens =  NSScreen.screens.compactMap({$0.localizedName})
                }
                .disabled(showOnAllDisplays)
                Defaults.Toggle("Automatically switch displays", key: .automaticallySwitchDisplay)
                .onChange(of: automaticallySwitchDisplay) {
                    NotificationCenter.default.post(name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                }
                .disabled(showOnAllDisplays)
            } header: {
                Text("System features")
            }
            
            Section {
                Picker(selection: $notchHeightMode, label:
                    Text("Notch display height")) {
                        Text("Match real notch size")
                            .tag(WindowHeightMode.matchRealNotchSize)
                        Text("Match menubar height")
                            .tag(WindowHeightMode.matchMenuBar)
                        Text("Custom height")
                            .tag(WindowHeightMode.custom)
                    }
                    .onChange(of: notchHeightMode) {
                        switch notchHeightMode {
                        case .matchRealNotchSize:
                            notchHeight = 38
                        case .matchMenuBar:
                            notchHeight = 44
                        case .custom:
                            notchHeight = 38
                        }
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                if notchHeightMode == .custom {
                    Slider(value: $notchHeight, in: 15...45, step: 1) {
                        Text("Custom notch size - \(notchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: notchHeight) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
                Picker("Non-notch display height", selection: $nonNotchHeightMode) {
                    Text("Match menubar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Match real notch size")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Custom height")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: nonNotchHeightMode) {
                    switch nonNotchHeightMode {
                    case .matchMenuBar:
                        nonNotchHeight = 24
                    case .matchRealNotchSize:
                        nonNotchHeight = 32
                    case .custom:
                        nonNotchHeight = 32
                    }
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
                if nonNotchHeightMode == .custom {
                    Slider(value: $nonNotchHeight, in: 0...40, step: 1) {
                        Text("Custom notch size - \(nonNotchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: nonNotchHeight) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            } header: {
                Text("Notch Height")
            }
            
            NotchBehaviour()
            
            gestureControls()
        }
        .toolbar {
            Button("Quit app") {
                NSApp.terminate(self)
            }
            .controlSize(.extraLarge)
        }
        .navigationTitle("General")
        .onChange(of: openNotchOnHover) {
            if !openNotchOnHover {
                enableGestures = true
            }
        }
    }
    
    @ViewBuilder
    func gestureControls() -> some View {
        Section {
            Defaults.Toggle("Enable gestures", key: .enableGestures)
                .disabled(!openNotchOnHover)
            if enableGestures {
                Toggle("Media change with horizontal gestures", isOn: .constant(false))
                    .disabled(true)
                Defaults.Toggle("Close gesture", key: .closeGestureEnabled)
                Slider(value: $gestureSensitivity, in: 100...300, step: 100) {
                    HStack {
                        Text("Gesture sensitivity")
                        Spacer()
                        Text(Defaults[.gestureSensitivity] == 100 ? "High" : Defaults[.gestureSensitivity] == 200 ? "Medium" : "Low")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                Text("Gesture control")
                customBadge(text: "Beta")
            }
        } footer: {
            Text("Two-finger swipe up on notch to close, two-finger swipe down on notch to open when **Open notch on hover** option is disabled")
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
    
    @ViewBuilder
    func NotchBehaviour() -> some View {
        Section {
            Defaults.Toggle("Extend hover area", key: .extendHoverArea)
            Defaults.Toggle("Enable haptics", key: .enableHaptics)
            Defaults.Toggle("Open notch on hover", key: .openNotchOnHover)
            Toggle("Remember last tab", isOn: $coordinator.openLastTabByDefault)
            if openNotchOnHover {
                Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1) {
                    HStack {
                        Text("Minimum hover duration")
                        Spacer()
                        Text("\(minimumHoverDuration, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
        } header: {
            Text("Notch behavior")
        }
    }
}

struct Charge: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle("Show battery indicator", key: .showBatteryIndicator)
                Defaults.Toggle("Show power status notifications", key: .showPowerStatusNotifications)
            } header: {
                Text("General")
            }
            Section {
                Defaults.Toggle("Show battery percentage", key: .showBatteryPercentage)
                Defaults.Toggle("Show power status icons", key: .showPowerStatusIcons)
            } header: {
                Text("Battery Information")
            }
        }
        .navigationTitle("Battery")
    }
}

struct Downloads: View {
    @Default(.selectedDownloadIndicatorStyle) var selectedDownloadIndicatorStyle
    @Default(.selectedDownloadIconStyle) var selectedDownloadIconStyle
    var body: some View {
        Form {
            warningBadge("We don't support downloads yet", "It will be supported later on.")
            Section {
                Defaults.Toggle("Show download progress", key: .enableDownloadListener)
                    .disabled(true)
                Defaults.Toggle("Enable Safari Downloads", key: .enableSafariDownloads)
                    .disabled(!Defaults[.enableDownloadListener])
                Picker("Download indicator style", selection: $selectedDownloadIndicatorStyle) {
                    Text("Progress bar")
                        .tag(DownloadIndicatorStyle.progress)
                    Text("Percentage")
                        .tag(DownloadIndicatorStyle.percentage)
                }
                Picker("Download icon style", selection: $selectedDownloadIconStyle) {
                    Text("Only app icon")
                        .tag(DownloadIconStyle.onlyAppIcon)
                    Text("Only download icon")
                        .tag(DownloadIconStyle.onlyIcon)
                    Text("Both")
                        .tag(DownloadIconStyle.iconAndAppIcon)
                }
                
            } header: {
                HStack {
                    Text("Download indicators")
                    comingSoonTag()
                }
            }
            Section {
                List {
                    ForEach([].indices, id: \.self) { index in
                        Text("\(index)")
                    }
                }
                .frame(minHeight: 96)
                .overlay {
                    if true {
                        Text("No excluded apps")
                            .foregroundStyle(Color(.secondaryLabelColor))
                    }
                }
                .actionBar(padding: 0) {
                    Group {
                        Button {} label: {
                            Image(systemName: "plus")
                                .frame(width: 25, height: 16, alignment: .center)
                                .contentShape(Rectangle())
                                .foregroundStyle(.secondary)
                        }
                        
                        Divider()
                        Button {} label: {
                            Image(systemName: "minus")
                                .frame(width: 20, height: 16, alignment: .center)
                                .contentShape(Rectangle())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                HStack(spacing: 4) {
                    Text("Exclude apps")
                    comingSoonTag()
                }
            }
        }
        .navigationTitle("Downloads")
    }
}

struct HUD: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Default(.inlineHUD) var inlineHUD
    @Default(.enableGradient) var enableGradient
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    var body: some View {
        Form {
            Section {
                Toggle("Enable HUD replacement", isOn: $coordinator.hudReplacement)
            } header: {
                Text("General")
            }
            Section {
                Picker("HUD style", selection: $inlineHUD) {
                    Text("Default")
                        .tag(false)
                    Text("Inline")
                        .tag(true)
                }
                .onChange(of: Defaults[.inlineHUD]) {
                    if Defaults[.inlineHUD] {
                        withAnimation {
                            Defaults[.systemEventIndicatorShadow] = false
                            Defaults[.enableGradient] = false
                        }
                    }
                }
                Picker("Progressbar style", selection: $enableGradient) {
                    Text("Hierarchical")
                        .tag(false)
                    Text("Gradient")
                        .tag(true)
                }
                Defaults.Toggle("Enable glowing effect", key: .systemEventIndicatorShadow)
                Defaults.Toggle("Use accent color", key: .systemEventIndicatorUseAccent)
            } header: {
                HStack {
                    Text("Appearance")
                }
            }
        }
        .navigationTitle("HUDs")
    }
}

struct Media: View {
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles
    
    var body: some View {
        Form {
            Section {
                Picker("Music Source", selection: $mediaController) {
                    ForEach(availableMediaControllers) { controller in
                        Text(controller.rawValue).tag(controller)
                    }
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }
            } header: {
                Text("Media Source")
            } footer: {
                if MusicManager.shared.isNowPlayingDeprecated {
                    HStack {
                        Text("YouTube Music requires this third-party app to be installed: ")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Link("https://github.com/th-ch/youtube-music", destination: URL(string: "https://github.com/th-ch/youtube-music")!)
                            .font(.caption)
                            .foregroundColor(.blue) // Ensures it's visibly a link
                    }
                } else {
                    Text("'Now Playing' was the only option on previous versions and works with all media apps.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            Section {
                Toggle(
                    "Enable music live activity",
                    isOn: $coordinator.musicLiveActivityEnabled
                )
                .animation(.easeInOut, value: coordinator.musicLiveActivityEnabled)
                
                Toggle("Enable sneak peek", isOn: $enableSneakPeek)
                Picker("Sneak Peek Style", selection: $sneakPeekStyles){
                    ForEach(SneakPeekStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }.disabled(!enableSneakPeek)
                HStack {
                    Stepper(value: $waitInterval, in: 0...10, step: 1) {
                        HStack {
                            Text("Media inactivity timeout")
                            Spacer()
                            Text("\(Defaults[.waitInterval], specifier: "%.0f") seconds")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Media playback live activity")
            }

            Picker(selection: $hideNotchOption, label:
                HStack {
                    Text("Hide DynamicIsland Options")
                    customBadge(text: "Beta")
                }) {
                    Text("Always hide in fullscreen").tag(HideNotchOption.always)
                    Text("Hide only when NowPlaying app is in fullscreen").tag(HideNotchOption.nowPlayingOnly)
                    Text("Never hide").tag(HideNotchOption.never)
                }
                .onChange(of: hideNotchOption) { _, newValue in
                    Defaults[.alwaysHideInFullscreen] = newValue == .always
                    Defaults[.enableFullscreenMediaDetection] = newValue != .never
                }
        }
        .navigationTitle("Media")
    }
    
    // Only show controller options that are available on this macOS version
    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }
}

struct CalendarSettings: View {
    @ObservedObject private var calendarManager = CalendarManager()
    @Default(.showCalendar) var showCalendar: Bool

    var body: some View {
        Form {
            if calendarManager.authorizationStatus != .fullAccess {
                Text("Calendar access is denied. Please enable it in System Settings.")
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding()
                Button("Open System Settings") {
                    if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(settingsURL)
                    }
                }
            } else {
                Toggle("Show calendar", isOn: $showCalendar)
                Section(header: Text("Select Calendars")) {
                    List {
                        ForEach(calendarManager.allCalendars, id: \.id) { calendar in
                            Toggle(isOn: Binding(
                                get: { calendarManager.getCalendarSelected(calendar) },
                                set: { isSelected in
                                    Task {
                                        await calendarManager.setCalendarSelected(calendar, isSelected: isSelected)
                                    }
                                }
                            )) {
                                Text(calendar.title)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            Task {
                await calendarManager.checkCalendarAuthorization()
            }
        }
        // Add navigation title if it's missing or adjust as needed
        .navigationTitle("Calendar")
    }
}

struct TimerSettings: View {
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.enableTimerFeature) var enableTimerFeature
    @AppStorage("customTimerDuration") private var customTimerDuration: Double = 600 // 10 minutes default
    @State private var customMinutes: Int = 10
    @State private var customSeconds: Int = 0
    
    var body: some View {
        Form {
            Section {
                Defaults.Toggle("Enable timer feature", key: .enableTimerFeature)
                
                if enableTimerFeature {
                    Toggle(
                        "Enable timer live activity",
                        isOn: $coordinator.timerLiveActivityEnabled
                    )
                    .animation(.easeInOut, value: coordinator.timerLiveActivityEnabled)
                }
            } header: {
                Text("Timer Feature")
            } footer: {
                Text("Enable or disable the timer functionality in the Dynamic Island. The live activity toggle controls whether timer progress is shown in the expanded view.")
            }
            
            if enableTimerFeature {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Custom Timer Duration")
                            .font(.headline)
                        
                        HStack(spacing: 16) {
                            VStack {
                                Text("Minutes")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                                
                                Picker(selection: $customMinutes, label: Text("Minutes")) {
                                    ForEach(0...59, id: \.self) { minute in
                                        Text("\(minute)").tag(minute)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 80, height: 40)
                            }
                            
                            VStack {
                                Text("Seconds")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                                
                                Picker(selection: $customSeconds, label: Text("Seconds")) {
                                    ForEach(0...59, id: \.self) { second in
                                        Text("\(second)").tag(second)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 80, height: 40)
                            }
                        }
                        
                        HStack {
                            Text("Current custom timer: \(customTimerDisplayText)")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Update") {
                                customTimerDuration = Double(customMinutes * 60 + customSeconds)
                            }
                            .disabled(customMinutes == 0 && customSeconds == 0)
                        }
                    }
                } header: {
                    Text("Custom Timer")
                } footer: {
                    Text("Set a custom duration for the timer. This will be used when you press the 'Custom' button in the timer interface.")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Timer Sound")
                                .font(.system(size: 16, weight: .medium))
                            Spacer()
                            Button("Choose File") {
                                selectCustomTimerSound()
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        if let customTimerSoundPath = UserDefaults.standard.string(forKey: "customTimerSoundPath") {
                            Text("Custom: \(URL(fileURLWithPath: customTimerSoundPath).lastPathComponent)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Default: dynamic.m4a")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Button("Reset to Default") {
                            UserDefaults.standard.removeObject(forKey: "customTimerSoundPath")
                        }
                        .buttonStyle(.bordered)
                        .disabled(UserDefaults.standard.string(forKey: "customTimerSoundPath") == nil)
                    }
                } header: {
                    Text("Timer Sound")
                } footer: {
                    Text("Choose a custom sound file that will play when the timer completes. Supported formats: MP3, M4A, WAV, AIFF.")
                }
            }
        }
        .navigationTitle("Timer")
        .onAppear {
            let totalMinutes = Int(customTimerDuration) / 60
            customMinutes = totalMinutes
            customSeconds = Int(customTimerDuration) % 60
        }
    }
    
    private var customTimerDisplayText: String {
        let totalMinutes = Int(customTimerDuration) / 60
        let seconds = Int(customTimerDuration) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        } else if minutes > 0 {
            return "\(minutes):\(String(format: "%02d", seconds))"
        } else {
            return "\(seconds)s"
        }
    }
    
    private func selectCustomTimerSound() {
        let panel = NSOpenPanel()
        panel.title = "Select Timer Sound"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                UserDefaults.standard.set(url.path, forKey: "customTimerSoundPath")
            }
        }
    }
}

struct About: View {
    @State private var showBuildNumber: Bool = false
    let updaterController: SPUStandardUpdaterController
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack {
            Form {
                Section {
                    HStack {
                        Text("Release name")
                        Spacer()
                        Text(Defaults[.releaseName])
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        if showBuildNumber {
                            Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                                .foregroundStyle(.secondary)
                        }
                        Text(Bundle.main.releaseVersionNumber ?? "unkown")
                            .foregroundStyle(.secondary)
                    }
                    .onTapGesture {
                        withAnimation {
                            showBuildNumber.toggle()
                        }
                    }
                } header: {
                    Text("Version info")
                }
                
                UpdaterSettingsView(updater: updaterController.updater)
                
                HStack(spacing: 30) {
                    Spacer(minLength: 0)
                    Button {
                        NSWorkspace.shared.open(sponsorPage)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "cup.and.saucer.fill")
                                .imageScale(.large)
                            Text("Support Us")
                                .foregroundStyle(.white)
                        }
                        .contentShape(Rectangle())
                    }
                    Spacer(minLength: 0)
                    Button {
                        NSWorkspace.shared.open(productPage)
                    } label: {
                        VStack(spacing: 5) {
                            Image("Github")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18)
                            Text("GitHub")
                                .foregroundStyle(.white)
                        }
                        .contentShape(Rectangle())
                    }
                    Spacer(minLength: 0)
                }
                .buttonStyle(PlainButtonStyle())
            }
            VStack(spacing: 0) {
                Divider()
                Text("Made with 🫶🏻 by not so boring not.people")
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
                    .padding(.bottom, 7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .toolbar {
//            Button("Welcome window") {
//                openWindow(id: "onboarding")
//            }
//            .controlSize(.extraLarge)
            CheckForUpdatesView(updater: updaterController.updater)
        }
        .navigationTitle("About")
    }
}

struct Shelf: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle("Enable shelf", key: .dynamicShelf)
                Defaults.Toggle("Open shelf tab by default if items added", key: .openShelfByDefault)
            } header: {
                HStack {
                    Text("General")
                }
            }
        }
        .navigationTitle("Shelf")
    }
}

struct Extensions: View {
    @EnvironmentObject var extensionManager: DynamicIslandExtensionManager
    @State private var effectTrigger: Bool = false
    var body: some View {
        Form {
            //warningBadge("We don't support extensions yet") // Uhhhh You do? <><><> Oori.S
            Section {
                List {
                    ForEach(extensionManager.installedExtensions.indices, id: \.self) { index in
                        let item = extensionManager.installedExtensions[index]
                        HStack {
                            AppIcon(for: item.bundleIdentifier)
                                .resizable()
                                .frame(width: 24, height: 24)
                            Text(item.name)
                            ListItemPopover {
                                Text("Description")
                            }
                            Spacer(minLength: 0)
                            HStack(spacing: 6) {
                                Circle()
                                    .frame(width: 6, height: 6)
                                    .foregroundColor(isExtensionRunning(item.bundleIdentifier) ? .green : item.status == .disabled ? .gray : .red)
                                    .conditionalModifier(isExtensionRunning(item.bundleIdentifier)) { view in
                                        view
                                            .shadow(color: .green, radius: 3)
                                    }
                                Text(isExtensionRunning(item.bundleIdentifier) ? "Running" : item.status == .disabled ? "Disabled" : "Stopped")
                                    .contentTransition(.numericText())
                                    .foregroundStyle(.secondary)
                                    .font(.footnote)
                            }
                            .frame(width: 60, alignment: .leading)
                            
                            Menu(content: {
                                Button("Restart") {
                                    let ws = NSWorkspace.shared
                                    
                                    if let ext = ws.runningApplications.first(where: { $0.bundleIdentifier == item.bundleIdentifier }) {
                                        ext.terminate()
                                    }
                                    
                                    if let appURL = ws.urlForApplication(withBundleIdentifier: item.bundleIdentifier) {
                                        ws.openApplication(at: appURL, configuration: .init(), completionHandler: nil)
                                    }
                                }
                                .keyboardShortcut("R", modifiers: .command)
                                Button("Disable") {
                                    if let ext = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == item.bundleIdentifier }) {
                                        ext.terminate()
                                    }
                                    extensionManager.installedExtensions[index].status = .disabled
                                }
                                .keyboardShortcut("D", modifiers: .command)
                                Divider()
                                Button("Uninstall", role: .destructive) {
                                    //
                                }
                            }, label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(.secondary)
                            })
                            .controlSize(.regular)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.vertical, 5)
                    }
                }
                .frame(minHeight: 120)
                .actionBar {
                    Button {} label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                            Text("Add manually")
                        }
                        .foregroundStyle(.secondary)
                    }
                    .disabled(true)
                    Spacer()
                    Button {
                        withAnimation(.linear(duration: 1)) {
                            effectTrigger.toggle()
                        } completion: {
                            effectTrigger.toggle()
                        }
                        extensionManager.checkIfExtensionsAreInstalled()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .rotationEffect(effectTrigger ? .degrees(360) : .zero)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .controlSize(.small)
                .buttonStyle(PlainButtonStyle())
                .overlay {
                    if extensionManager.installedExtensions.isEmpty {
                        Text("No extension installed")
                            .foregroundStyle(Color(.secondaryLabelColor))
                            .padding(.bottom, 22)
                    }
                }
            } header: {
                HStack(spacing: 0) {
                    Text("Installed extensions")
                    if !extensionManager.installedExtensions.isEmpty {
                        Text(" – \(extensionManager.installedExtensions.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Extensions")
        // TipsView()
        // .padding(.horizontal, 19)
    }
}

struct Appearance: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.mirrorShape) var mirrorShape
    @Default(.sliderColor) var sliderColor
    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.customVisualizers) var customVisualizers
    @Default(.selectedVisualizer) var selectedVisualizer
    let icons: [String] = ["logo2"]
    @State private var selectedIcon: String = "logo2"
    @State private var selectedListVisualizer: CustomVisualizer? = nil
    
    @State private var isPresented: Bool = false
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var speed: CGFloat = 1.0
    var body: some View {
        Form {
            Section {
                Toggle("Always show tabs", isOn: $coordinator.alwaysShowTabs)
                Defaults.Toggle("Settings icon in notch", key: .settingsIconInNotch)
                Defaults.Toggle("Enable window shadow", key: .enableShadow)
                Defaults.Toggle("Corner radius scaling", key: .cornerRadiusScaling)
                Defaults.Toggle("Use simpler close animation", key: .useModernCloseAnimation)
            } header: {
                Text("General")
            }
            
            Section {
                Defaults.Toggle("Enable colored spectrograms", key: .coloredSpectrogram)
                Defaults
                    .Toggle("Player tinting", key: .playerColorTinting)
                Defaults.Toggle("Enable blur effect behind album art", key: .lightingEffect)
                Picker("Slider color", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(option.rawValue)
                    }
                }
            } header: {
                Text("Media")
            }
            
            Section {
                Toggle(
                    "Use music visualizer spectrogram",
                    isOn: $useMusicVisualizer.animation()
                )
                .disabled(true)
                if !useMusicVisualizer {
                    if customVisualizers.count > 0 {
                        Picker(
                            "Selected animation",
                            selection: $selectedVisualizer
                        ) {
                            ForEach(
                                customVisualizers,
                                id: \.self
                            ) { visualizer in
                                Text(visualizer.name)
                                    .tag(visualizer)
                            }
                        }
                    } else {
                        HStack {
                            Text("Selected animation")
                            Spacer()
                            Text("No custom animation available")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Custom music live activity animation")
                    customBadge(text: "Coming soon")
                }
            }
            
            Section {
                List {
                    ForEach(customVisualizers, id: \.self) { visualizer in
                        HStack {
                            LottieView(state: LUStateData(type: .loadedFrom(visualizer.url), speed: visualizer.speed, loopMode: .loop))
                                .frame(width: 30, height: 30, alignment: .center)
                            Text(visualizer.name)
                            Spacer(minLength: 0)
                            if selectedVisualizer == visualizer {
                                Text("selected")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 8)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.vertical, 2)
                        .background(
                            selectedListVisualizer != nil ? selectedListVisualizer == visualizer ? Color.accentColor : Color.clear : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedListVisualizer == visualizer {
                                selectedListVisualizer = nil
                                return
                            }
                            selectedListVisualizer = visualizer
                        }
                    }
                }
                .safeAreaPadding(
                    EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0)
                )
                .frame(minHeight: 120)
                .actionBar {
                    HStack(spacing: 5) {
                        Button {
                            name = ""
                            url = ""
                            speed = 1.0
                            isPresented.toggle()
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        Divider()
                        Button {
                            if selectedListVisualizer != nil {
                                let visualizer = selectedListVisualizer!
                                selectedListVisualizer = nil
                                customVisualizers.remove(at: customVisualizers.firstIndex(of: visualizer)!)
                                if visualizer == selectedVisualizer && customVisualizers.count > 0 {
                                    selectedVisualizer = customVisualizers[0]
                                }
                            }
                        } label: {
                            Image(systemName: "minus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                    }
                }
                .controlSize(.small)
                .buttonStyle(PlainButtonStyle())
                .overlay {
                    if customVisualizers.isEmpty {
                        Text("No custom visualizer")
                            .foregroundStyle(Color(.secondaryLabelColor))
                            .padding(.bottom, 22)
                    }
                }
                .sheet(isPresented: $isPresented) {
                    VStack(alignment: .leading) {
                        Text("Add new visualizer")
                            .font(.largeTitle.bold())
                            .padding(.vertical)
                        TextField("Name", text: $name)
                        TextField("Lottie JSON URL", text: $url)
                        HStack {
                            Text("Speed")
                            Spacer(minLength: 80)
                            Text("\(speed, specifier: "%.1f")s")
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                            Slider(value: $speed, in: 0...2, step: 0.1)
                        }
                        .padding(.vertical)
                        HStack {
                            Button {
                                isPresented.toggle()
                            } label: {
                                Text("Cancel")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            
                            Button {
                                let visualizer: CustomVisualizer = .init(
                                    UUID: UUID(),
                                    name: name,
                                    url: URL(string: url)!,
                                    speed: speed
                                )
                                
                                if !customVisualizers.contains(visualizer) {
                                    customVisualizers.append(visualizer)
                                }
                                
                                isPresented.toggle()
                            } label: {
                                Text("Add")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(BorderedProminentButtonStyle())
                        }
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .controlSize(.extraLarge)
                    .padding()
                }
            } header: {
                HStack(spacing: 0) {
                    Text("Custom vizualizers (Lottie)")
                    if !Defaults[.customVisualizers].isEmpty {
                        Text(" – \(Defaults[.customVisualizers].count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section {
                Defaults.Toggle("Enable boring mirror", key: .showMirror)
                    .disabled(!checkVideoInput())
                Picker("Mirror shape", selection: $mirrorShape) {
                    Text("Circle")
                        .tag(MirrorShapeEnum.circle)
                    Text("Square")
                        .tag(MirrorShapeEnum.rectangle)
                }
                Defaults.Toggle("Show cool face animation while inactivity", key: .showNotHumanFace)
            } header: {
                HStack {
                    Text("Additional features")
                }
            }
            
            Section {
                HStack {
                    ForEach(icons, id: \.self) { icon in
                        Spacer()
                        VStack {
                            Image(icon)
                                .resizable()
                                .frame(width: 80, height: 80)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .circular)
                                        .strokeBorder(
                                            icon == selectedIcon ? Color.accentColor : .clear,
                                            lineWidth: 2.5
                                        )
                                )
                            
                            Text("Default")
                                .fontWeight(.medium)
                                .font(.caption)
                                .foregroundStyle(icon == selectedIcon ? .white : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(icon == selectedIcon ? Color.accentColor : .clear)
                                )
                        }
                        .onTapGesture {
                            withAnimation {
                                selectedIcon = icon
                            }
                            NSApp.applicationIconImage = NSImage(named: icon)
                        }
                        Spacer()
                    }
                }
                .disabled(true)
            } header: {
                HStack {
                    Text("App icon")
                    customBadge(text: "Coming soon")
                }
            }
        }
        .navigationTitle("Appearance")
    }
    
    func checkVideoInput() -> Bool {
        if let _ = AVCaptureDevice.default(for: .video) {
            return true
        }
        
        return false
    }
}

struct Shortcuts: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Toggle Sneak Peek:", name: .toggleSneakPeek)
            } header: {
                Text("Media")
            } footer: {
                Text("Sneak Peek shows the media title and artist under the notch for a few seconds.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Section {
                KeyboardShortcuts.Recorder("Toggle Notch Open:", name: .toggleNotchOpen)
            }
            Section {
                KeyboardShortcuts.Recorder("Start Demo Timer:", name: .startDemoTimer)
            } header: {
                Text("Timer")
            } footer: {
                Text("Starts a 5-minute demo timer to test the timer live activity feature.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .navigationTitle("Shortcuts")
    }
}

struct Stats: View {
    @ObservedObject var statsManager = StatsManager.shared
    @Default(.enableStatsFeature) var enableStatsFeature
    
    var body: some View {
        Form {
            Section {
                Defaults.Toggle("Enable system stats monitoring", key: .enableStatsFeature)
                    .onChange(of: enableStatsFeature) { _, newValue in
                        if newValue {
                            statsManager.startMonitoring()
                        } else {
                            statsManager.stopMonitoring()
                        }
                    }
            } header: {
                Text("General")
            } footer: {
                Text("When enabled, the Stats tab will display real-time CPU, Memory, and GPU usage graphs. This feature requires system permissions and may use additional battery.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            
            if enableStatsFeature {
                Section {
                    HStack {
                        Text("Monitoring Status")
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statsManager.isMonitoring ? .green : .red)
                                .frame(width: 8, height: 8)
                            Text(statsManager.isMonitoring ? "Active" : "Stopped")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if statsManager.isMonitoring {
                        HStack {
                            Text("CPU Usage")
                            Spacer()
                            Text(statsManager.cpuUsageString)
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack {
                            Text("Memory Usage")
                            Spacer()
                            Text(statsManager.memoryUsageString)
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack {
                            Text("GPU Usage")
                            Spacer()
                            Text(statsManager.gpuUsageString)
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack {
                            Text("Last Updated")
                            Spacer()
                            Text(statsManager.lastUpdated, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("System Performance")
                }
                
                Section {
                    HStack {
                        Button(statsManager.isMonitoring ? "Stop Monitoring" : "Start Monitoring") {
                            if statsManager.isMonitoring {
                                statsManager.stopMonitoring()
                            } else {
                                statsManager.startMonitoring()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .foregroundColor(statsManager.isMonitoring ? .red : .blue)
                        
                        Spacer()
                        
                        Button("Clear Data") {
                            clearStatsData()
                        }
                        .buttonStyle(.bordered)
                        .disabled(statsManager.isMonitoring)
                    }
                } header: {
                    Text("Controls")
                }
            }
        }
        .navigationTitle("Stats")
    }
    
    private func clearStatsData() {
        statsManager.cpuHistory = Array(repeating: 0.0, count: 30)
        statsManager.memoryHistory = Array(repeating: 0.0, count: 30) 
        statsManager.gpuHistory = Array(repeating: 0.0, count: 30)
    }
}

func proFeatureBadge() -> some View {
    Text("Upgrade to Pro")
        .foregroundStyle(Color(red: 0.545, green: 0.196, blue: 0.98))
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 4).stroke(Color(red: 0.545, green: 0.196, blue: 0.98), lineWidth: 1))
}

func comingSoonTag() -> some View {
    Text("Coming soon")
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func customBadge(text: String) -> some View {
    Text(text)
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func warningBadge(_ text: String, _ description: String) -> some View {
    Section {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text(text)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct ClipboardSettings: View {
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @Default(.enableClipboardManager) var enableClipboardManager
    @Default(.clipboardHistorySize) var clipboardHistorySize
    @Default(.showClipboardIcon) var showClipboardIcon
    
    var body: some View {
        Form {
            Section {
                Defaults.Toggle("Enable Clipboard Manager", key: .enableClipboardManager)
                    .onChange(of: enableClipboardManager) { enabled in
                        if enabled {
                            clipboardManager.startMonitoring()
                        } else {
                            clipboardManager.stopMonitoring()
                        }
                    }
            } header: {
                Text("Clipboard Manager")
            } footer: {
                Text("Monitor clipboard changes and keep a history of recent copies. Use Cmd+Shift+V to quickly access clipboard history.")
            }
            
            if enableClipboardManager {
                Section {
                    Defaults.Toggle("Show Clipboard Icon", key: .showClipboardIcon)
                    
                    HStack {
                        Text("History Size")
                        Spacer()
                        Picker("History Size", selection: $clipboardHistorySize) {
                            Text("3 items").tag(3)
                            Text("5 items").tag(5)
                            Text("7 items").tag(7)
                            Text("10 items").tag(10)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 100)
                    }
                    
                    HStack {
                        Text("Current Items")
                        Spacer()
                        Text("\(clipboardManager.clipboardHistory.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Monitoring Status")
                        Spacer()
                        Text(clipboardManager.isMonitoring ? "Active" : "Stopped")
                            .foregroundColor(clipboardManager.isMonitoring ? .green : .secondary)
                    }
                } header: {
                    Text("Settings")
                } footer: {
                    Text("The clipboard icon appears in the header next to the settings gear when enabled. Use the global shortcut Cmd+Shift+V or click the icon to access history.")
                }
                
                Section {
                    Button("Clear Clipboard History") {
                        clipboardManager.clearHistory()
                    }
                    .foregroundColor(.red)
                    .disabled(clipboardManager.clipboardHistory.isEmpty)
                } header: {
                    Text("Actions")
                } footer: {
                    Text("This will permanently delete all stored clipboard history. The clipboard button is located to the left of the settings gear in the header.")
                }
                
                if !clipboardManager.clipboardHistory.isEmpty {
                    Section {
                        ForEach(clipboardManager.clipboardHistory) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: item.type.icon)
                                        .foregroundColor(.blue)
                                        .frame(width: 16)
                                    Text(item.type.displayName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(timeAgoString(from: item.timestamp))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Text(item.preview)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Current History")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Clipboard")
        .onAppear {
            if enableClipboardManager && !clipboardManager.isMonitoring {
                clipboardManager.startMonitoring()
            }
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

#Preview {
    HUD()
}
