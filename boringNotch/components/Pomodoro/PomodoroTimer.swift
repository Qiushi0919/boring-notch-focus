//
//  PomodoroTimer.swift
//  boringNotch
//
//  A wall-clock based focus timer that survives app relaunches and sleep.
//

import AppKit
import Combine
import Defaults
import Foundation
@preconcurrency import UserNotifications

enum PomodoroPhase: String {
    case focus
    case shortBreak

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Break"
        }
    }

    var localizedTitle: String {
        AppL10n.text(title)
    }

    var icon: String {
        switch self {
        case .focus: return "timer"
        case .shortBreak: return "cup.and.saucer.fill"
        }
    }
}

@MainActor
final class PomodoroTimer: ObservableObject {
    static let shared = PomodoroTimer()

    @Published private(set) var phase: PomodoroPhase = .focus
    @Published private(set) var isRunning = false
    @Published private(set) var remainingSeconds = 25 * 60
    @Published private(set) var sessionDuration = 25 * 60
    @Published private(set) var completedFocusSessions = 0

    private enum StorageKey {
        static let phase = "pomodoro.timer.phase"
        static let isRunning = "pomodoro.timer.isRunning"
        static let remainingSeconds = "pomodoro.timer.remainingSeconds"
        static let sessionDuration = "pomodoro.timer.sessionDuration"
        static let endDate = "pomodoro.timer.endDate"
        static let completedFocusSessions = "pomodoro.timer.completedFocusSessions"
    }

    private let storage = UserDefaults.standard
    private var endDate: Date?
    private var ticker: AnyCancellable?

    private init() {
        restoreState()

        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                self?.tick(at: date)
            }
    }

    var formattedRemainingTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var progress: Double {
        guard sessionDuration > 0 else { return 0 }
        return 1 - (Double(remainingSeconds) / Double(sessionDuration))
    }

    func start() {
        guard Defaults[.pomodoroEnabled], !isRunning else { return }

        if remainingSeconds <= 0 {
            resetCurrentSession()
        }

        requestNotificationAuthorizationIfNeeded()
        endDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        isRunning = true
        persistState()
    }

    func pause() {
        guard isRunning else { return }
        updateRemainingTime(at: Date())
        isRunning = false
        endDate = nil
        persistState()
    }

    func toggleRunning() {
        isRunning ? pause() : start()
    }

    func resetCurrentSession() {
        isRunning = false
        endDate = nil
        sessionDuration = configuredDuration(for: phase)
        remainingSeconds = sessionDuration
        persistState()
    }

    func restartCycle() {
        phase = .focus
        completedFocusSessions = 0
        resetCurrentSession()
    }

    func skipToNextSession() {
        advanceToNextSession(completedNaturally: false)
    }

    func configurationDidChange() {
        guard !isRunning else { return }
        sessionDuration = configuredDuration(for: phase)
        remainingSeconds = sessionDuration
        persistState()
    }

    private func tick(at date: Date) {
        guard isRunning else { return }
        updateRemainingTime(at: date)

        if remainingSeconds == 0 {
            advanceToNextSession(completedNaturally: true)
        }
    }

    private func updateRemainingTime(at date: Date) {
        guard let endDate else { return }
        remainingSeconds = max(0, Int(ceil(endDate.timeIntervalSince(date))))
    }

    private func advanceToNextSession(completedNaturally: Bool) {
        let finishedPhase = phase

        if completedNaturally && finishedPhase == .focus {
            completedFocusSessions += 1
        }

        isRunning = false
        endDate = nil
        phase = finishedPhase == .focus ? .shortBreak : .focus
        sessionDuration = configuredDuration(for: phase)
        remainingSeconds = sessionDuration

        if completedNaturally {
            sendCompletionFeedback(for: finishedPhase)
        }

        persistState()

        if completedNaturally && Defaults[.pomodoroAutoStartNextSession] {
            start()
        }
    }

    private func configuredDuration(for phase: PomodoroPhase) -> Int {
        let minutes = phase == .focus
            ? Defaults[.pomodoroFocusMinutes]
            : Defaults[.pomodoroBreakMinutes]
        return max(1, minutes) * 60
    }

    private func restoreState() {
        if let rawPhase = storage.string(forKey: StorageKey.phase),
           let restoredPhase = PomodoroPhase(rawValue: rawPhase)
        {
            phase = restoredPhase
        }

        completedFocusSessions = max(
            0,
            storage.integer(forKey: StorageKey.completedFocusSessions)
        )

        let configured = configuredDuration(for: phase)
        let savedDuration = storage.integer(forKey: StorageKey.sessionDuration)
        sessionDuration = savedDuration > 0 ? savedDuration : configured

        let savedRemaining = storage.integer(forKey: StorageKey.remainingSeconds)
        remainingSeconds = savedRemaining > 0 ? min(savedRemaining, sessionDuration) : sessionDuration

        if storage.bool(forKey: StorageKey.isRunning),
           let savedEndDate = storage.object(forKey: StorageKey.endDate) as? Date
        {
            endDate = savedEndDate
            isRunning = true
            tick(at: Date())
        }
    }

    private func persistState() {
        storage.set(phase.rawValue, forKey: StorageKey.phase)
        storage.set(isRunning, forKey: StorageKey.isRunning)
        storage.set(remainingSeconds, forKey: StorageKey.remainingSeconds)
        storage.set(sessionDuration, forKey: StorageKey.sessionDuration)
        storage.set(endDate, forKey: StorageKey.endDate)
        storage.set(completedFocusSessions, forKey: StorageKey.completedFocusSessions)
    }

    private func requestNotificationAuthorizationIfNeeded() {
        guard Defaults[.pomodoroNotificationsEnabled] else { return }

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    private func sendCompletionFeedback(for finishedPhase: PomodoroPhase) {
        NSSound(named: NSSound.Name("Glass"))?.play()

        guard Defaults[.pomodoroNotificationsEnabled] else { return }

        let content = UNMutableNotificationContent()
        content.title = AppL10n.text(
            finishedPhase == .focus ? "Focus session complete" : "Break complete"
        )
        content.body = finishedPhase == .focus
            ? AppL10n.text("Nice work. Time for a short break.")
            : AppL10n.text("Ready for another focus session?")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "pomodoro.session.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
