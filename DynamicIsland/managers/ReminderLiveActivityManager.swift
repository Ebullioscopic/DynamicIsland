//
//  ReminderLiveActivityManager.swift
//  DynamicIsland
//
//  Created by GitHub Copilot on 2025-11-12.
//

import Combine
import Defaults
import EventKit
import Foundation
import CoreGraphics

@MainActor
final class ReminderLiveActivityManager: ObservableObject {
    struct ReminderEntry: Equatable {
        let event: EventModel
        let triggerDate: Date
        let leadTime: TimeInterval
    }

    static let shared = ReminderLiveActivityManager()
    static let standardIconName = "calendar.badge.clock"
    static let criticalIconName = "calendar.badge.exclamationmark"
    static let listRowHeight: CGFloat = 30
    static let listRowSpacing: CGFloat = 8
    static let listTopPadding: CGFloat = 14
    static let listBottomPadding: CGFloat = 10
    static let baselineMinimalisticBottomPadding: CGFloat = 3

    @Published private(set) var activeReminder: ReminderEntry?
    @Published private(set) var currentDate: Date = Date()
    @Published private(set) var upcomingEntries: [ReminderEntry] = []
    @Published private(set) var activeWindowReminders: [ReminderEntry] = []

    private var nextReminder: ReminderEntry?
    private var cancellables = Set<AnyCancellable>()
    private var tickerTask: Task<Void, Never>? { didSet { oldValue?.cancel() } }
    private var evaluationTask: Task<Void, Never>?
    private var fallbackRefreshTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var pendingRefreshTask: Task<Void, Never>?
    private var pendingRefreshForce = false
    private var pendingRefreshToken = UUID()
    private var lastRefreshDate: Date?
    private let minimumRefreshInterval: TimeInterval = 60
    private let refreshDebounceInterval: TimeInterval = 0.3
    private var refreshTaskToken = UUID()
    private var hasShownCriticalSneakPeek = false

    private let calendarService: CalendarServiceProviding
    private let calendarManager = CalendarManager.shared

    var isActive: Bool { activeReminder != nil }

    private init(calendarService: CalendarServiceProviding = CalendarService()) {
        self.calendarService = calendarService
        setupObservers()
        scheduleRefresh(force: true)
    }

    private func setupObservers() {
        Defaults.publisher(.enableReminderLiveActivity, options: [])
            .sink { [weak self] change in
                guard let self else { return }
                if change.newValue {
                    self.scheduleRefresh(force: true)
                } else {
                    self.deactivateReminder()
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.reminderLeadTime, options: [])
            .sink { [weak self] _ in
                guard let self else { return }
                self.scheduleRefresh(force: true)
            }
            .store(in: &cancellables)

        Defaults.publisher(.reminderPresentationStyle, options: [])
            .sink { [weak self] _ in
                guard let self else { return }
                // Presentation change does not alter scheduling, but ensure state publishes for UI updates.
                if let reminder = self.activeReminder {
                    self.activeReminder = reminder
                }
            }
            .store(in: &cancellables)

        calendarManager.$allCalendars
            .sink { [weak self] _ in
                guard let self else { return }
                self.scheduleRefresh(force: true)
            }
            .store(in: &cancellables)

        calendarManager.$events
            .sink { [weak self] _ in
                guard let self else { return }
                self.scheduleRefresh(force: false)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .sink { [weak self] _ in
                guard let self else { return }
                self.scheduleRefresh(force: true)
            }
            .store(in: &cancellables)
    }

    private func cancelAllTimers() {
        tickerTask = nil
        evaluationTask?.cancel()
        evaluationTask = nil
        fallbackRefreshTask?.cancel()
        fallbackRefreshTask = nil
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil
        pendingRefreshForce = false
        refreshTask?.cancel()
        refreshTask = nil
        hasShownCriticalSneakPeek = false
    }

    private func deactivateReminder() {
        nextReminder = nil
        activeReminder = nil
        upcomingEntries = []
        activeWindowReminders = []
        cancelAllTimers()
    }

    private func selectedCalendarIDs() -> [String] {
        calendarManager.allCalendars
            .filter { calendarManager.getCalendarSelected($0) }
            .map { $0.id }
    }

    private func shouldHide(_ event: EventModel) -> Bool {
        if event.isAllDay && Defaults[.hideAllDayEvents] {
            return true
        }
        if case let .reminder(completed) = event.type,
           completed && Defaults[.hideCompletedReminders] {
            return true
        }
        return false
    }

    private func makeEntry(from event: EventModel, leadMinutes: Int, referenceDate: Date) -> ReminderEntry? {
        guard event.start > referenceDate else { return nil }
        let leadSeconds = max(1, leadMinutes) * 60
        let trigger = event.start.addingTimeInterval(TimeInterval(-leadSeconds))
        return ReminderEntry(event: event, triggerDate: trigger, leadTime: TimeInterval(leadSeconds))
    }

    private func scheduleEvaluation(at date: Date) {
        evaluationTask?.cancel()
        let delay = date.timeIntervalSinceNow
        guard delay > 0 else {
            Task { await self.evaluateCurrentState(at: Date()) }
            return
        }

        evaluationTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self.evaluateCurrentState(at: Date())
        }
    }

    private func scheduleFallbackRefresh() {
        fallbackRefreshTask?.cancel()
        let delay: TimeInterval = 15 * 60
        fallbackRefreshTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self.scheduleRefresh(force: true)
        }
    }

    private func scheduleRefresh(force: Bool) {
        pendingRefreshForce = pendingRefreshForce || force
        pendingRefreshToken = UUID()
        let token = pendingRefreshToken

        refreshTask?.cancel()
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(self.refreshDebounceInterval * 1_000_000_000))
            } catch {
                return
            }
            await self.executeScheduledRefresh(token: token)
        }
    }

    private func executeScheduledRefresh(token: UUID) async {
        guard pendingRefreshToken == token else { return }
        pendingRefreshTask = nil

        if Task.isCancelled {
            return
        }

        let now = Date()
        let force = pendingRefreshForce
        if !force, let last = lastRefreshDate {
            let elapsed = now.timeIntervalSince(last)
            if elapsed < minimumRefreshInterval {
                let remaining = max(minimumRefreshInterval - elapsed, refreshDebounceInterval)
                pendingRefreshToken = UUID()
                let nextToken = pendingRefreshToken
                pendingRefreshTask = Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                    } catch {
                        return
                    }
                    await self.executeScheduledRefresh(token: nextToken)
                }
                return
            }
        }

        pendingRefreshForce = false
        lastRefreshDate = now

        refreshTask?.cancel()
        let taskToken = UUID()
        refreshTaskToken = taskToken
        let task = Task { [weak self] in
            guard let self else { return }
            await self.refreshUpcomingReminder(force: force)
        }
        refreshTask = task
        defer {
            if refreshTaskToken == taskToken {
                refreshTask = nil
            }
        }
        _ = try? await task.value
    }

    private func startTickerIfNeeded() {
        guard tickerTask == nil else { return }
        tickerTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.handleTick()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
            }
        }
    }

    private func stopTicker() {
        tickerTask = nil
    }

    private func handleEntrySelection(_ entry: ReminderEntry?, referenceDate: Date) {
        fallbackRefreshTask?.cancel()
        nextReminder = entry
        hasShownCriticalSneakPeek = false
        Task { await self.evaluateCurrentState(at: referenceDate) }
    }

    private func refreshFromEvents(_ events: [EventModel], referenceDate: Date) {
        let leadMinutes = Defaults[.reminderLeadTime]
        let upcoming = events
            .filter { !shouldHide($0) }
            .compactMap { makeEntry(from: $0, leadMinutes: leadMinutes, referenceDate: referenceDate) }
            .sorted { $0.triggerDate < $1.triggerDate }

        upcomingEntries = upcoming
        updateActiveWindowReminders(for: referenceDate)

        guard let first = upcoming.first else {
            deactivateReminder()
            scheduleFallbackRefresh()
            return
        }

        handleEntrySelection(first, referenceDate: referenceDate)
    }

    func requestRefresh(force: Bool = false) {
        scheduleRefresh(force: force)
    }

    func refreshUpcomingReminder(force: Bool = false) async {
        guard Defaults[.enableReminderLiveActivity] else {
            deactivateReminder()
            return
        }

        let now = Date()

        if !force, let entry = nextReminder, entry.event.start > now {
            await evaluateCurrentState(at: now)
            return
        }

        let calendars = selectedCalendarIDs()
        guard !calendars.isEmpty else {
            deactivateReminder()
            return
        }

        let windowEnd = Calendar.current.date(byAdding: .hour, value: 24, to: now) ?? now.addingTimeInterval(24 * 60 * 60)
        let events = await calendarService.events(from: now, to: windowEnd, calendars: calendars)
        await MainActor.run {
            self.refreshFromEvents(events, referenceDate: now)
        }
    }

    func evaluateCurrentState(at date: Date) async {
        guard Defaults[.enableReminderLiveActivity] else {
            deactivateReminder()
            return
        }

        currentDate = date
        updateActiveWindowReminders(for: date)

        guard var entry = nextReminder else {
            activeReminder = nil
            stopTicker()
            return
        }

        if entry.event.start <= date {
            activeReminder = nil
            nextReminder = nil
            stopTicker()
            hasShownCriticalSneakPeek = false
            scheduleRefresh(force: true)
            return
        }

        if entry.triggerDate <= date {
            if entry.triggerDate > entry.event.start {
                entry = ReminderEntry(event: entry.event, triggerDate: entry.event.start, leadTime: entry.leadTime)
                nextReminder = entry
            }
            if activeReminder != entry {
                activeReminder = entry
                DynamicIslandViewCoordinator.shared.toggleSneakPeek(
                    status: true,
                    type: .reminder,
                    duration: Defaults[.reminderSneakPeekDuration],
                    value: 0,
                    icon: ReminderLiveActivityManager.standardIconName
                )
                hasShownCriticalSneakPeek = false
            }

            let criticalWindow = TimeInterval(Defaults[.reminderSneakPeekDuration])
            let timeRemaining = entry.event.start.timeIntervalSince(date)
            if criticalWindow > 0 && timeRemaining > 0 {
                if timeRemaining <= criticalWindow {
                    if !hasShownCriticalSneakPeek {
                        let displayDuration = min(criticalWindow, max(timeRemaining - 2, 0))
                        if displayDuration > 0 {
                            DynamicIslandViewCoordinator.shared.toggleSneakPeek(
                                status: true,
                                type: .reminder,
                                duration: displayDuration,
                                value: 0,
                                icon: ReminderLiveActivityManager.criticalIconName
                            )
                            hasShownCriticalSneakPeek = true
                        }
                    }
                } else {
                    hasShownCriticalSneakPeek = false
                }
            }
            startTickerIfNeeded()
        } else {
            if activeReminder != nil {
                activeReminder = nil
            }
            stopTicker()
            hasShownCriticalSneakPeek = false
            scheduleEvaluation(at: entry.triggerDate)
        }
    }

    @MainActor
    private func handleTick() async {
        let now = Date()
        if abs(currentDate.timeIntervalSince(now)) >= 0.5 {
            currentDate = now
        }
        await evaluateCurrentState(at: now)
    }

    private func updateActiveWindowReminders(for date: Date) {
        let filtered = upcomingEntries.filter { entry in
            entry.triggerDate <= date && entry.event.start >= date
        }
        if filtered != activeWindowReminders {
            activeWindowReminders = filtered
        }
    }

    static func additionalHeight(forRowCount rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        let rows = CGFloat(rowCount)
        let spacing = CGFloat(max(rowCount - 1, 0)) * listRowSpacing
        let bottomDelta = max(listBottomPadding - baselineMinimalisticBottomPadding, 0)
        return listTopPadding + rows * listRowHeight + spacing + bottomDelta
    }

}

extension ReminderLiveActivityManager.ReminderEntry: Identifiable {
    var id: String { event.id }
}
