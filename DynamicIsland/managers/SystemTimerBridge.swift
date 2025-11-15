//
//  SystemTimerBridge.swift
//  DynamicIsland
//
//  Mirrors the macOS Clock timer into the custom timer live activity.
//

import AppKit
import ApplicationServices
import Combine
import Defaults
import Foundation
import OSLog
import os

final class SystemTimerBridge {
    static let shared = SystemTimerBridge()

    private let logger = os.Logger(subsystem: "com.Ebullioscopic.Atoll", category: "SystemTimerBridge")

    private struct TimerMetadata: Equatable {
        enum State: Int {
            case stopped = 1
            case running = 2
            case paused = 3
            case fired = 4
            case unknown = 0

            var isActive: Bool {
                switch self {
                case .running, .paused:
                    return true
                default:
                    return false
                }
            }
        }

        let identifier: String
        let title: String
        let duration: TimeInterval
        let lastModified: Date?
        let firedDate: Date?
        let state: State
    }

    private struct ParsedTimerString {
        let raw: String
        let remaining: TimeInterval
        let paused: Bool
    }

    private let domain = "com.apple.mobiletimerd" as CFString
    private let preferencesPath = (NSHomeDirectory() as NSString)
        .appendingPathComponent("Library/Preferences/com.apple.mobiletimerd.plist")
    private let queue = DispatchQueue(label: "com.dynamicisland.systemtimer.bridge", qos: .userInitiated)

    private var metadata: TimerMetadata?
    private var initialTotalDuration: TimeInterval?
    private var latestRemaining: TimeInterval?
    private var latestPaused: Bool = false

    private var logProcess: Process?
    private var logPipe: Pipe?
    private var logBuffer = Data()
    private var logRestartWorkItem: DispatchWorkItem?
    private var logPreferredName: String?
    private var logPreferredDuration: TimeInterval?
    private var logIdentifier: String?
    private var logDidCompleteActiveTimer = false
    private var nonJSONLogLineCount = 0

    private var menuExtra: AXUIElement?
    private var fileDescriptor: CInt = -1
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var ticker: DispatchSourceTimer?
    private var defaultsCancellable: AnyCancellable?

    private var didWarnAboutAccessibility = false

    private init() {
        logDebug("Initializing SystemTimerBridge (mirror enabled: \(Defaults[.mirrorSystemTimer]))")
        defaultsCancellable = Defaults.publisher(.mirrorSystemTimer, options: [])
            .sink { [weak self] change in
                if change.newValue {
                    self?.logDebug("mirrorSystemTimer enabled via Defaults change")
                    self?.startIfNeeded()
                } else {
                    self?.logDebug("mirrorSystemTimer disabled via Defaults change; stopping monitor")
                    self?.stopMonitoring(clearTimer: true)
                }
            }

        if Defaults[.mirrorSystemTimer] {
            startIfNeeded()
        }
    }

    private func logDebug(_ message: String) {
        logger.debug("\(message, privacy: OSLogPrivacy.public)")
    }

    private func logInfo(_ message: String) {
        logger.info("\(message, privacy: OSLogPrivacy.public)")
    }

    private func logError(_ message: String) {
        logger.error("\(message, privacy: OSLogPrivacy.public)")
    }

    private func startIfNeeded() {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.isMonitoring else { return }
            self.logInfo("Starting monitoring pipeline")

            self.refreshMetadata()
            self.startFileMonitor()

            let logStarted = self.startLogStream()
            let hasAccessibility = AXIsProcessTrusted()

            self.logDebug("Log stream started: \(logStarted), AX trusted: \(hasAccessibility)")

            if !logStarted {
                if hasAccessibility {
                    self.logInfo("Falling back to Accessibility polling ticker")
                    self.setupTicker()
                } else {
                    self.logError("Unable to start log stream and missing Accessibility permission; timer mirroring inactive")
                    self.postAccessibilityWarningIfNeeded()
                }
            } else if !hasAccessibility {
                self.logDebug("Log stream active but Accessibility not trusted; AX fallback disabled")
                self.postAccessibilityWarningIfNeeded()
            }
        }
    }

    private var isMonitoring: Bool {
        logProcess != nil || ticker != nil || fileMonitor != nil
    }

    private func stopMonitoring(clearTimer: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.logInfo("Stopping monitoring pipeline (clearTimer: \(clearTimer))")

            self.stopLogStream()

            self.ticker?.cancel()
            self.ticker = nil

            self.fileMonitor?.cancel()
            self.fileMonitor = nil

            if self.fileDescriptor != -1 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }

            self.menuExtra = nil
            self.initialTotalDuration = nil
            self.metadata = nil
            self.latestRemaining = nil
            self.latestPaused = false
            self.logPreferredName = nil
            self.logPreferredDuration = nil
            self.logIdentifier = nil
            self.logDidCompleteActiveTimer = false
            self.logRestartWorkItem?.cancel()
            self.logRestartWorkItem = nil

            if clearTimer {
                self.logDebug("Clearing external timer state via TimerManager")
                DispatchQueue.main.async {
                    TimerManager.shared.endExternalTimer(triggerSmoothClose: false)
                }
            }
        }
    }

    private func setupTicker() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(150))
        timer.setEventHandler { [weak self] in
            self?.pollMenuExtra()
        }
        timer.resume()
        ticker = timer
        logInfo("Accessibility ticker active")
    }

    @discardableResult
    private func startLogStream() -> Bool {
        if let process = logProcess, process.isRunning {
            return true
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        let predicate = "subsystem == \"com.apple.mobiletimer.logging\""
        process.arguments = [
            "stream",
            "--style",
            "ndjson",
            "--predicate",
            predicate,
            "--level",
            "debug"
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        logBuffer.removeAll(keepingCapacity: false)
        nonJSONLogLineCount = 0
        logPipe = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { [weak self] in
                self?.consumeLogData(data)
            }
        }

        process.terminationHandler = { [weak self] _ in
            self?.queue.async { [weak self] in
                self?.handleLogStreamTermination()
            }
        }

        do {
            try process.run()
            logProcess = process
            logInfo("Log stream started (pid: \(process.processIdentifier))")
            return true
        } catch {
            logError("Failed to start log stream: \(error.localizedDescription)")
            outputPipe.fileHandleForReading.readabilityHandler = nil
            outputPipe.fileHandleForReading.closeFile()
            logPipe = nil
            return false
        }
    }

    private func stopLogStream() {
        logRestartWorkItem?.cancel()
        logRestartWorkItem = nil

        logPipe?.fileHandleForReading.readabilityHandler = nil
        logPipe?.fileHandleForReading.closeFile()
        logPipe = nil

        if let process = logProcess {
            process.terminationHandler = nil
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
                logInfo("Log stream terminated (pid: \(process.processIdentifier))")
            }
        }

        logProcess = nil
        logBuffer.removeAll(keepingCapacity: false)
    }

    private func handleLogStreamTermination() {
        logPipe?.fileHandleForReading.readabilityHandler = nil
        logPipe?.fileHandleForReading.closeFile()
        logPipe = nil
        logProcess = nil
        logBuffer.removeAll(keepingCapacity: false)
        logError("Log stream exited unexpectedly; scheduling restart")

        guard Defaults[.mirrorSystemTimer] else { return }

        if AXIsProcessTrusted(), ticker == nil {
            setupTicker()
        }

        scheduleLogStreamRestart()
    }

    private func scheduleLogStreamRestart() {
        logRestartWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.logRestartWorkItem = nil
            let started = self.startLogStream()
            if !started, AXIsProcessTrusted(), self.ticker == nil {
                self.setupTicker()
            }
        }

        logRestartWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 2.0, execute: workItem)
        logDebug("Scheduled log stream restart in 2s")
    }

    private func consumeLogData(_ data: Data) {
        logBuffer.append(data)

        while let newlineIndex = logBuffer.firstIndex(of: UInt8(10)) {
            let lineData = Data(logBuffer[..<newlineIndex])
            let removalIndex = logBuffer.index(after: newlineIndex)
            logBuffer.removeSubrange(..<removalIndex)
            guard !lineData.isEmpty else { continue }
            processLogLine(lineData)
        }
    }

    private func processLogLine(_ data: Data) {
        if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
           let payload = jsonObject as? [String: Any] {
            handleLogEvent(payload)
            return
        }

        handleDiscardedLogLine(data)
    }

    private func handleDiscardedLogLine(_ data: Data) {
        nonJSONLogLineCount += 1

        let shouldLogSample = nonJSONLogLineCount <= 3 || nonJSONLogLineCount.isMultiple(of: 50)
        guard shouldLogSample else { return }

        if let string = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !string.isEmpty {
            logDebug("Discarded non-JSON log line (count: \(nonJSONLogLineCount)): \(string)")
        } else {
            logDebug("Discarded non-JSON log line (count: \(nonJSONLogLineCount))")
        }
    }

    private func startFileMonitor() {
        let fd = open(preferencesPath, O_EVTONLY)
        guard fd != -1 else {
            logError("Unable to monitor preferences at \(preferencesPath)")
            return
        }

        fileDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.refreshMetadata()
        }

        source.setCancelHandler { [weak self] in
            guard let fd = self?.fileDescriptor, fd != -1 else { return }
            close(fd)
            self?.fileDescriptor = -1
        }

        source.resume()
        fileMonitor = source
        logDebug("Preferences file monitor armed")
    }

    private func pollMenuExtra() {
        guard Defaults[.mirrorSystemTimer] else { return }
        guard !TimerManager.shared.hasManualTimerRunning else {
            logDebug("Skipping AX poll: manual timer running")
            return
        }

        if logProcess != nil, logIdentifier != nil {
            logDebug("Skipping AX poll: log stream already tracking timer")
            return
        }

        if menuExtra == nil {
            menuExtra = locateTimerMenuExtra()

            if menuExtra == nil {
                logDebug("Timer menu extra not found via AX")
                handleMissingMenuExtra()
                return
            }
            logDebug("Timer menu extra located via AX")
        }

        guard let element = menuExtra else { return }
        guard let parsed = extractTimerString(from: element) else {
            menuExtra = nil
            logDebug("Failed to extract timer string from AX element; clearing reference")
            handleMissingMenuExtra()
            return
        }

        latestRemaining = parsed.remaining
        latestPaused = parsed.paused

        logDebug("AX parsed remaining: \(parsed.remaining), paused: \(parsed.paused)")

        applyTimerUpdate(remaining: parsed.remaining, paused: parsed.paused)
    }

    private func applyTimerUpdate(remaining: TimeInterval, paused: Bool) {
        guard Defaults[.mirrorSystemTimer] else { return }
        guard !TimerManager.shared.hasManualTimerRunning else {
            logDebug("Ignoring timer update while manual timer active")
            return
        }
        guard remaining.isFinite else { return }

        logDebug("Applying timer update (remaining: \(remaining), paused: \(paused))")

        let durationFromMetadata = logPreferredDuration ?? metadata?.duration ?? 0
        if let metadata, metadata.state == .running || metadata.state == .paused {
            if durationFromMetadata > 0, (initialTotalDuration ?? 0) < durationFromMetadata {
                initialTotalDuration = durationFromMetadata
            }
        }

        if initialTotalDuration == nil {
            initialTotalDuration = max(durationFromMetadata, remaining)
        } else if remaining > (initialTotalDuration ?? 0) {
            initialTotalDuration = remaining
        }

        let baseTotal = max(durationFromMetadata, remaining > 0 ? remaining : 0)
        let total = initialTotalDuration ?? baseTotal

        let trimmedLogName = logPreferredName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMetadataName = metadata?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName: String

        if let name = trimmedLogName, !name.isEmpty {
            displayName = name
        } else if let name = trimmedMetadataName, !name.isEmpty {
            displayName = name
        } else {
            displayName = "Clock Timer"
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if TimerManager.shared.isExternalTimerActive {
                self.logDebug("Updating existing external timer (total: \(total))")
                TimerManager.shared.updateExternalTimer(
                    remaining: remaining,
                    totalDuration: total,
                    isPaused: paused,
                    name: displayName
                )
            } else {
                self.logInfo("Adopting system timer as external source (name: \(displayName))")
                TimerManager.shared.adoptExternalTimer(
                    name: displayName,
                    totalDuration: total,
                    remaining: remaining,
                    isPaused: paused
                )
            }

            if remaining <= 0 {
                self.logDidCompleteActiveTimer = true
                self.logInfo("System timer reported completion")
                TimerManager.shared.completeExternalTimer()
            } else {
                self.logDidCompleteActiveTimer = false
            }
        }
    }

    private func handleMissingMenuExtra() {
        guard logIdentifier == nil else { return }
        guard TimerManager.shared.isExternalTimerActive else { return }

        logDebug("Timer menu extra missing; ending external timer")
        DispatchQueue.main.async {
            TimerManager.shared.endExternalTimer(triggerSmoothClose: true)
        }
    }

    private func handleLogEvent(_ payload: [String: Any]) {
        guard Defaults[.mirrorSystemTimer] else { return }
        guard !TimerManager.shared.hasManualTimerRunning else {
            logDebug("Ignoring log event while manual timer active")
            return
        }
        guard let message = payload["eventMessage"] as? String, !message.isEmpty else { return }

        logDebug("Log event: \(message)")

        if message.contains("scheduled timers:") {
            handleScheduledTimersMessage(message)
        }

        if message.contains("Timer will fire") {
            handleTimerWillFireMessage(message)
        }

        if message.contains("remainingTime:") {
            handleRemainingTimeMessage(message)
        }

        if message.contains("next timer changed:") {
            handleNextTimerChangedMessage(message)
        }

        if message.contains("started timer:") {
            handleTimerStartedMessage(message)
        }
    }

    private func handleScheduledTimersMessage(_ message: String) {
        guard let identifier = captureFirstMatch(pattern: "TimerID:\\s*([A-F0-9\\-]+)", in: message) else {
            logDebug("Scheduled timers message without identifier; clearing state")
            clearLogState(triggerSmoothClose: true)
            return
        }

        logDebug("Scheduled timers message for ID: \(identifier)")
        setLogIdentifier(identifier)

        if let title = captureFirstMatch(pattern: "Title:\\s*([^,]+)", in: message) {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != "(null)" {
                logPreferredName = trimmed
                logDebug("Updated timer name from log: \(trimmed)")
            }
        }

        if let durationString = captureFirstMatch(pattern: "duration:([0-9]+(?:\\.[0-9]+)?)", in: message),
           let duration = Double(durationString) {
            if let existing = logPreferredDuration {
                logPreferredDuration = max(existing, duration)
            } else {
                logPreferredDuration = duration
            }

            if (initialTotalDuration ?? 0) < duration {
                initialTotalDuration = duration
            }

            logDebug("Recorded duration from log: \(duration)")
        }

        if let stateString = captureFirstMatch(pattern: "state:([A-Za-z]+)", in: message) {
            let normalized = stateString.lowercased()
            logDebug("Timer state from log: \(normalized)")
            switch normalized {
            case "paused":
                latestPaused = true
                if let remaining = latestRemaining {
                    applyLogDrivenUpdate(remaining: remaining, isPaused: true)
                }
            case "running":
                latestPaused = false
                if let remaining = latestRemaining {
                    applyLogDrivenUpdate(remaining: remaining, isPaused: false)
                }
            case "fired":
                latestPaused = false
                applyLogDrivenUpdate(remaining: 0, isPaused: false)
                return
            case "stopped":
                latestPaused = false
                clearLogState(triggerSmoothClose: true)
                return
            default:
                break
            }
        }
    }

    private func handleTimerWillFireMessage(_ message: String) {
        guard logIdentifier != nil else { return }
                guard let minutesString = captureFirstMatch(pattern: "Timer will fire\\s+([0-9.]+)\\s+minutes?", in: message),
                            let minutes = Double(minutesString) else { return }

        let seconds = minutes * 60
        logDebug("Timer will fire in \(seconds) seconds")
        applyLogDrivenUpdate(remaining: seconds, isPaused: latestPaused)
    }

    private func handleRemainingTimeMessage(_ message: String) {
        guard let valueString = captureFirstMatch(pattern: "remainingTime:\\s*([-0-9.]+)", in: message),
              let remaining = Double(valueString) else { return }

        logDebug("Remaining time from log: \(remaining)")
        applyLogDrivenUpdate(remaining: remaining, isPaused: latestPaused)
    }

    private func handleNextTimerChangedMessage(_ message: String) {
        guard let token = captureFirstMatch(pattern: "next timer changed:\\s*([^\n]+)", in: message) else { return }
        let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: " <>"))
        if trimmed.isEmpty { return }

        logDebug("Next timer changed token: \(trimmed)")

        if trimmed.lowercased().contains("null") {
            clearLogState(triggerSmoothClose: true)
        } else {
            setLogIdentifier(trimmed)
        }
    }

    private func handleTimerStartedMessage(_ message: String) {
        guard let identifier = captureFirstMatch(pattern: "started timer:\\s*([A-F0-9\\-]+)", in: message) else { return }
        logDebug("Timer started for ID: \(identifier)")
        setLogIdentifier(identifier)
    }

    private func applyLogDrivenUpdate(remaining: TimeInterval, isPaused: Bool, nameOverride: String? = nil, durationOverride: TimeInterval? = nil) {
        guard Defaults[.mirrorSystemTimer] else { return }
        guard !TimerManager.shared.hasManualTimerRunning else { return }
        guard logIdentifier != nil else { return }

        if let nameOverride, !nameOverride.isEmpty {
            logPreferredName = nameOverride
            logDebug("Applying name override: \(nameOverride)")
        }

        if let durationOverride {
            if let existing = logPreferredDuration {
                logPreferredDuration = max(existing, durationOverride)
            } else {
                logPreferredDuration = durationOverride
            }
            logDebug("Applying duration override: \(durationOverride)")
        }

        latestPaused = isPaused
        latestRemaining = remaining
        logDebug("Log-driven update (remaining: \(remaining), paused: \(isPaused))")

        if let duration = logPreferredDuration, (initialTotalDuration ?? 0) < duration {
            initialTotalDuration = duration
        }

        if remaining > (initialTotalDuration ?? 0) {
            initialTotalDuration = remaining
        }

        applyTimerUpdate(remaining: remaining, paused: isPaused)
    }

    private func setLogIdentifier(_ identifier: String) {
        let cleaned = identifier.trimmingCharacters(in: CharacterSet(charactersIn: " <>"))
        guard !cleaned.isEmpty else { return }

        if logIdentifier != cleaned {
            logInfo("Tracking system timer ID: \(cleaned)")
            logIdentifier = cleaned
            logDidCompleteActiveTimer = false
            initialTotalDuration = nil
            latestRemaining = nil
            logPreferredDuration = nil
            logPreferredName = nil
        }
    }

    private func clearLogState(triggerSmoothClose: Bool) {
        logInfo("Clearing log-derived timer state (smooth close: \(triggerSmoothClose))")
        let didComplete = logDidCompleteActiveTimer

        logIdentifier = nil
        logPreferredName = nil
        logPreferredDuration = nil
        initialTotalDuration = nil
        latestRemaining = nil
        latestPaused = false
        logDidCompleteActiveTimer = false

        guard triggerSmoothClose else { return }

        DispatchQueue.main.async {
            guard TimerManager.shared.isExternalTimerActive else { return }
            if didComplete {
                self.logDebug("Timer finished; scheduling delayed cleanup")
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                    if TimerManager.shared.isExternalTimerActive {
                        self.logDebug("Delayed cleanup firing; ending external timer")
                        TimerManager.shared.endExternalTimer(triggerSmoothClose: false)
                    }
                }
            } else {
                self.logDebug("Ending external timer immediately")
                TimerManager.shared.endExternalTimer(triggerSmoothClose: true)
            }
        }
    }

    private func captureFirstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let swiftRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[swiftRange])
    }

    private func refreshMetadata() {
        let previous = metadata
        metadata = fetchMetadata()

        if metadata == nil {
            initialTotalDuration = nil
            logDebug("No active metadata found in preferences")
        }

        guard let metadata, metadata != previous else { return }

        logDebug("Metadata updated from preferences (title: \(metadata.title), duration: \(metadata.duration))")

        if metadata.duration > 0, (initialTotalDuration ?? 0) < metadata.duration {
            initialTotalDuration = metadata.duration
        }

        if TimerManager.shared.isExternalTimerActive {
            let remaining = latestRemaining ?? metadata.duration
            DispatchQueue.main.async {
                self.logDebug("Syncing metadata update with TimerManager (remaining: \(remaining))")
                TimerManager.shared.updateExternalTimer(
                    remaining: remaining,
                    totalDuration: metadata.duration,
                    isPaused: self.latestPaused,
                    name: metadata.title
                )
            }
        }
    }

    private func fetchMetadata() -> TimerMetadata? {
        CFPreferencesAppSynchronize(domain)
        guard let container = CFPreferencesCopyAppValue("MTTimers" as CFString, domain) as? [String: Any],
              let rawTimers = container["MTTimers"] as? [[String: Any]] else {
            return nil
        }

        let records: [TimerMetadata] = rawTimers.compactMap { entry in
            guard let timer = entry["$MTTimer"] as? [String: Any] else { return nil }
            let identifier = timer["MTTimerID"] as? String ?? UUID().uuidString
            let rawTitle = (timer["MTTimerTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (rawTitle?.isEmpty == false) ? rawTitle! : "Clock Timer"
            let duration = timer["MTTimerDuration"] as? TimeInterval ?? 0
            let lastModified = timer["MTTimerLastModifiedDate"] as? Date
            let firedDate = timer["MTTimerFiredDate"] as? Date
            let stateRaw = timer["MTTimerState"] as? Int ?? 0
            let state = TimerMetadata.State(rawValue: stateRaw) ?? .unknown

            return TimerMetadata(
                identifier: identifier,
                title: title,
                duration: duration,
                lastModified: lastModified,
                firedDate: firedDate,
                state: state
            )
        }

        if let active = records.first(where: { $0.state.isActive }) {
            logDebug("Found active timer in preferences (state: \(active.state.rawValue))")
            return active
        }

        return records.sorted { (lhs, rhs) -> Bool in
            (lhs.lastModified ?? .distantPast) > (rhs.lastModified ?? .distantPast)
        }.first
    }

    private func locateTimerMenuExtra() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        guard let menuBar: AXUIElement = copyAttribute(kAXMenuBarAttribute as CFString, from: systemWide) else {
            return nil
        }

        guard let items: [AXUIElement] = copyAttribute(kAXChildrenAttribute as CFString, from: menuBar) else {
            return nil
        }

        for item in items {
            if isTimerMenuExtra(item) {
                return item
            }
        }

        return nil
    }

    private func isTimerMenuExtra(_ element: AXUIElement) -> Bool {
        if let identifier: String = copyAttribute(kAXIdentifierAttribute as CFString, from: element),
           identifier.lowercased().contains("timer") {
            return true
        }

        if let title: String = copyAttribute(kAXTitleAttribute as CFString, from: element),
           matchesTimerText(title) {
            return true
        }

        if let value: String = copyAttribute(kAXValueAttribute as CFString, from: element),
           matchesTimerText(value) {
            return true
        }

        if let children: [AXUIElement] = copyAttribute(kAXChildrenAttribute as CFString, from: element) {
            for child in children {
                if let value: String = copyAttribute(kAXValueAttribute as CFString, from: child), matchesTimerText(value) {
                    return true
                }
                if let title: String = copyAttribute(kAXTitleAttribute as CFString, from: child), matchesTimerText(title) {
                    return true
                }
            }
        }

        return false
    }

    private func extractTimerString(from element: AXUIElement) -> ParsedTimerString? {
        if let value: String = copyAttribute(kAXValueAttribute as CFString, from: element),
           let parsed = parseTimerString(value) {
            return parsed
        }

        if let title: String = copyAttribute(kAXTitleAttribute as CFString, from: element),
           let parsed = parseTimerString(title) {
            return parsed
        }

        if let children: [AXUIElement] = copyAttribute(kAXChildrenAttribute as CFString, from: element) {
            for child in children {
                if let value: String = copyAttribute(kAXValueAttribute as CFString, from: child),
                   let parsed = parseTimerString(value) {
                    return parsed
                }
                if let title: String = copyAttribute(kAXTitleAttribute as CFString, from: child),
                   let parsed = parseTimerString(title) {
                    return parsed
                }
            }
        }

        return nil
    }

    private func parseTimerString(_ raw: String) -> ParsedTimerString? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        let paused = lower.contains("pause") || lower.contains("stopped")

        if let seconds = extractSeconds(from: trimmed) {
            return ParsedTimerString(raw: trimmed, remaining: seconds, paused: paused)
        }

        return nil
    }

    private func extractSeconds(from text: String) -> TimeInterval? {
        let numericPattern = "[0-9]+(?::[0-9]{2}){0,2}"
        if let match = text.range(of: numericPattern, options: .regularExpression) {
            let token = String(text[match])
            let parts = token.split(separator: ":").compactMap { Double($0) }
            switch parts.count {
            case 3:
                return parts[0] * 3600 + parts[1] * 60 + parts[2]
            case 2:
                return parts[0] * 60 + parts[1]
            case 1:
                return parts[0]
            default:
                break
            }
        }

        let suffixPattern = "([0-9]+)([hms])"
        let regex = try? NSRegularExpression(pattern: suffixPattern, options: [])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex?.matches(in: text, options: [], range: range) ?? []

        guard !matches.isEmpty else { return nil }

        var total: TimeInterval = 0
        for match in matches {
            guard match.numberOfRanges == 3,
                  let valueRange = Range(match.range(at: 1), in: text),
                  let unitRange = Range(match.range(at: 2), in: text),
                  let value = Double(text[valueRange]) else { continue }

            switch text[unitRange] {
            case "h": total += value * 3600
            case "m": total += value * 60
            case "s": total += value
            default: break
            }
        }

        return total > 0 ? total : nil
    }

    private func matchesTimerText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.lowercased().contains("timer") {
            return true
        }

        let pattern = "[0-9]+(?::[0-9]{2}){0,2}"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    private func copyAttribute<T>(_ attribute: CFString, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success, let typed = value as? T else {
            return nil
        }
        return typed
    }

    private func postAccessibilityWarningIfNeeded() {
        guard !didWarnAboutAccessibility else { return }
        didWarnAboutAccessibility = true
        logError("Accessibility permission missing; prompt user to enable it")
        DispatchQueue.main.async {
            debugPrint("[SystemTimerBridge] Accessibility permission is required to mirror Clock timers. Grant access in System Settings → Privacy & Security → Accessibility.")
        }
    }
}
