//
//  OnboardingView.swift
//  boringNotch
//
//  Created by Alexander on 2025-06-23.
//

import AppKit
import ApplicationServices
import AVFoundation
import EventKit
import SwiftUI
import UserNotifications

enum OnboardingStep {
    case language
    case welcome
    case permissions
    case musicPermission
    case finished
}

private let calendarService = CalendarService()

struct OnboardingView: View {
    @State var step: OnboardingStep = .language
    @State private var languageRefreshToken = UUID()
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            switch step {
            case .language:
                LanguageSelectionView { language in
                    AppL10n.setLanguage(language)
                    languageRefreshToken = UUID()
                    withAnimation(.easeInOut(duration: 0.45)) {
                        step = .welcome
                    }
                }
                .transition(.opacity)

            case .welcome:
                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        step = .permissions
                    }
                }
                .transition(.opacity)

            case .permissions:
                PermissionCenterView {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        step = .musicPermission
                    }
                }
                .transition(.opacity)

            case .musicPermission:
                MusicControllerSelectionView(
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.45)) {
                            BoringViewCoordinator.shared.firstLaunch = false
                            step = .finished
                        }
                    }
                )
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
            }
        }
        .id(languageRefreshToken)
        .frame(width: 440, height: 640)
    }
}

struct LanguageSelectionView: View {
    @State private var selection = AppL10n.selectedLanguage
    let onContinue: (AppLanguage) -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 16)

            Image(systemName: "globe")
                .font(.system(size: 58, weight: .light))
                .foregroundStyle(Color.effectiveAccent)

            VStack(spacing: 6) {
                Text("选择语言")
                    .font(.title.bold())
                Text("Choose your language")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("稍后可以在设置中更改 · You can change this later in Settings")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                languageOption(
                    .system,
                    title: "跟随系统 / Follow System",
                    detail: "使用 Mac 当前的语言设置"
                )
                languageOption(
                    .simplifiedChinese,
                    title: "简体中文",
                    detail: "使用简体中文界面"
                )
                languageOption(
                    .english,
                    title: "English",
                    detail: "Use the English interface"
                )
            }
            .padding(.horizontal, 28)

            Spacer()

            Button {
                onContinue(selection)
            } label: {
                Text("继续 / Continue")
                    .frame(minWidth: 150)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }

    private func languageOption(
        _ language: AppLanguage,
        title: String,
        detail: String
    ) -> some View {
        Button {
            selection = language
        } label: {
            HStack(spacing: 14) {
                Image(systemName: selection == language ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selection == language ? Color.effectiveAccent : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 66)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(selection == language ? Color.effectiveAccent.opacity(0.14) : Color.secondary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(
                        selection == language ? Color.effectiveAccent.opacity(0.8) : Color.secondary.opacity(0.18),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private enum PermissionDisplayState {
    case granted
    case notRequested
    case denied
    case onDemand

    var title: String {
        switch self {
        case .granted:
            return AppL10n.text("Allowed")
        case .notRequested:
            return AppL10n.text("Not Requested")
        case .denied:
            return AppL10n.text("Not Allowed")
        case .onDemand:
            return AppL10n.text("Requested When Used")
        }
    }

    var icon: String {
        switch self {
        case .granted:
            return "checkmark.circle.fill"
        case .notRequested:
            return "circle.dashed"
        case .denied:
            return "exclamationmark.triangle.fill"
        case .onDemand:
            return "clock.badge.questionmark"
        }
    }

    var color: Color {
        switch self {
        case .granted:
            return .green
        case .notRequested:
            return .orange
        case .denied:
            return .red
        case .onDemand:
            return .blue
        }
    }
}

private struct PermissionStatusRow: View {
    let icon: String
    let title: String
    let detail: String
    let state: PermissionDisplayState
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.effectiveAccent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Label(state.title, systemImage: state.icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(state.color)
            }

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

struct PermissionCenterView: View {
    let onContinue: (() -> Void)?

    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var calendarStatus = EKEventStore.authorizationStatus(for: .event)
    @State private var remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
    @State private var musicAccessibilityAuthorized = AXIsProcessTrusted()
    @State private var helperAccessibilityAuthorized = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isRefreshing = false

    init(onContinue: (() -> Void)? = nil) {
        self.onContinue = onContinue
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.effectiveAccent)
                Text(AppL10n.text("Permission Center"))
                    .font(.title.bold())
                Text(
                    AppL10n.text(
                        "Grant only the permissions needed by the features you use. You can change them later in System Settings."
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
            }
            .padding(.top, 14)

            ScrollView {
                LazyVStack(spacing: 9) {
                    PermissionStatusRow(
                        icon: "calendar",
                        title: AppL10n.text("Calendar Access"),
                        detail: AppL10n.text("Shows your upcoming events in the calendar area."),
                        state: eventKitState(calendarStatus),
                        actionTitle: actionTitle(for: eventKitState(calendarStatus)),
                        action: { handleCalendarAction() }
                    )

                    PermissionStatusRow(
                        icon: "checklist",
                        title: AppL10n.text("Reminders Access"),
                        detail: AppL10n.text("Shows scheduled reminders together with calendar events."),
                        state: eventKitState(remindersStatus),
                        actionTitle: actionTitle(for: eventKitState(remindersStatus)),
                        action: { handleRemindersAction() }
                    )

                    PermissionStatusRow(
                        icon: "heart.fill",
                        title: AppL10n.text("QQ Music Controls"),
                        detail: AppL10n.text("Accessibility access lets the heart button control QQ Music."),
                        state: musicAccessibilityAuthorized ? .granted : .denied,
                        actionTitle: musicAccessibilityAuthorized ? nil : AppL10n.text("Request Access"),
                        action: { requestMusicAccessibility() }
                    )

                    PermissionStatusRow(
                        icon: "dial.medium.fill",
                        title: AppL10n.text("System HUD Controls"),
                        detail: AppL10n.text(
                            "The helper needs Accessibility access only when replacing the macOS volume and brightness HUD."
                        ),
                        state: helperAccessibilityAuthorized ? .granted : .denied,
                        actionTitle: helperAccessibilityAuthorized ? nil : AppL10n.text("Request Access"),
                        action: { requestHelperAccessibility() }
                    )

                    PermissionStatusRow(
                        icon: "bell.badge.fill",
                        title: AppL10n.text("Notifications"),
                        detail: AppL10n.text("Shows an alert when a focus or break session ends."),
                        state: notificationDisplayState,
                        actionTitle: actionTitle(for: notificationDisplayState),
                        action: { handleNotificationAction() }
                    )

                    PermissionStatusRow(
                        icon: "camera.fill",
                        title: AppL10n.text("Camera Access"),
                        detail: AppL10n.text("Optional. Used only for the notch mirror preview."),
                        state: cameraDisplayState,
                        actionTitle: actionTitle(for: cameraDisplayState),
                        action: { handleCameraAction() }
                    )

                    PermissionStatusRow(
                        icon: "music.note.list",
                        title: AppL10n.text("Music Automation"),
                        detail: AppL10n.text(
                            "macOS asks when the app first controls Apple Music or Spotify. QQ Music uses Accessibility instead."
                        ),
                        state: .onDemand,
                        actionTitle: AppL10n.text("Open Settings"),
                        action: { openPrivacySettings("Privacy_Automation") }
                    )
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
            }

            Text(
                AppL10n.text(
                    "If macOS blocks the app before it opens, go to System Settings → Privacy & Security and choose Open Anyway."
                )
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 22)

            HStack(spacing: 12) {
                Button {
                    Task { await refreshStatuses() }
                } label: {
                    Label(AppL10n.text("Refresh Status"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing)

                if let onContinue {
                    Button(AppL10n.text("Continue"), action: onContinue)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(AppL10n.text("Permissions"))
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
        .task {
            await refreshStatuses()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshStatuses() }
        }
    }

    private var cameraDisplayState: PermissionDisplayState {
        switch cameraStatus {
        case .authorized:
            return .granted
        case .notDetermined:
            return .notRequested
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    private var notificationDisplayState: PermissionDisplayState {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .notDetermined:
            return .notRequested
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    private func eventKitState(_ status: EKAuthorizationStatus) -> PermissionDisplayState {
        switch status {
        case .authorized, .fullAccess:
            return .granted
        case .notDetermined:
            return .notRequested
        case .denied, .restricted, .writeOnly:
            return .denied
        @unknown default:
            return .denied
        }
    }

    private func actionTitle(for state: PermissionDisplayState) -> String? {
        switch state {
        case .granted:
            return nil
        case .notRequested:
            return AppL10n.text("Request Access")
        case .denied, .onDemand:
            return AppL10n.text("Open Settings")
        }
    }

    @MainActor
    private func refreshStatuses() async {
        guard !isRefreshing else { return }
        isRefreshing = true

        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
        musicAccessibilityAuthorized = AXIsProcessTrusted()
        helperAccessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        notificationStatus = await currentNotificationStatus()

        isRefreshing = false
    }

    private func currentNotificationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private func handleCalendarAction() {
        if calendarStatus == .notDetermined {
            Task {
                _ = try? await calendarService.requestAccess(to: .event)
                await refreshStatuses()
            }
        } else {
            openPrivacySettings("Privacy_Calendars")
        }
    }

    private func handleRemindersAction() {
        if remindersStatus == .notDetermined {
            Task {
                _ = try? await calendarService.requestAccess(to: .reminder)
                await refreshStatuses()
            }
        } else {
            openPrivacySettings("Privacy_Reminders")
        }
    }

    private func requestMusicAccessibility() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        Task {
            try? await Task.sleep(for: .milliseconds(750))
            await refreshStatuses()
        }
    }

    private func requestHelperAccessibility() {
        Task {
            _ = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
            try? await Task.sleep(for: .milliseconds(750))
            await refreshStatuses()
        }
    }

    private func handleNotificationAction() {
        if notificationStatus == .notDetermined {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
                Task { await refreshStatuses() }
            }
        } else {
            openNotificationSettings()
        }
    }

    private func handleCameraAction() {
        if cameraStatus == .notDetermined {
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                await refreshStatuses()
            }
        } else {
            openPrivacySettings("Privacy_Camera")
        }
    }

    private func openPrivacySettings(_ anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openNotificationSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?bundleId=\(bundleIdentifier)",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]
        guard let url = candidates.compactMap(URL.init(string:)).first else { return }
        NSWorkspace.shared.open(url)
    }
}
