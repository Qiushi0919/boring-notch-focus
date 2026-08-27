//
//  PomodoroView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct PomodoroView: View {
    @ObservedObject private var timer = PomodoroTimer.shared

    private var tint: Color {
        timer.phase == .focus ? .orange : .mint
    }

    var body: some View {
        HStack(spacing: 30) {
            timerDial

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: timer.phase.icon)
                        .foregroundStyle(tint)
                    Text(timer.phase.localizedTitle)
                        .font(.headline)
                    Text(AppL10n.format("%lld completed", timer.completedFocusSessions))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                controls
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 36)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(AppL10n.text("Focus Timer")), \(timer.phase.localizedTitle), \(timer.formattedRemainingTime)")
    }

    private var timerDial: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 7)

            Circle()
                .trim(from: 0, to: min(max(timer.progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: timer.progress)

            VStack(spacing: 2) {
                Text(timer.formattedRemainingTime)
                    .font(.system(size: 23, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                Text(AppL10n.text(timer.isRunning ? "RUNNING" : "READY"))
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 104, height: 104)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                timer.toggleRunning()
            } label: {
                Label(
                    AppL10n.text(timer.isRunning ? "Pause" : "Start"),
                    systemImage: timer.isRunning ? "pause.fill" : "play.fill"
                )
                .frame(minWidth: 70)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)

            Button {
                timer.resetCurrentSession()
            } label: {
                Label(AppL10n.text("Reset"), systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)

            Button {
                timer.skipToNextSession()
            } label: {
                Label(AppL10n.text("Skip"), systemImage: "forward.end.fill")
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }
}

struct PomodoroLiveActivity: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var timer = PomodoroTimer.shared

    private var tint: Color {
        timer.phase == .focus ? .orange : .mint
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: min(max(timer.progress, 0), 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: timer.phase.icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(
                width: max(0, vm.effectiveClosedNotchHeight - 12),
                height: max(0, vm.effectiveClosedNotchHeight - 12)
            )

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            Text(timer.formattedRemainingTime)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(tint)
                .frame(width: 54, alignment: .leading)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .accessibilityLabel("\(timer.phase.localizedTitle)，\(timer.formattedRemainingTime)")
    }
}

struct PomodoroSettings: View {
    @ObservedObject private var timer = PomodoroTimer.shared
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @Default(.pomodoroEnabled) private var pomodoroEnabled
    @Default(.pomodoroFocusMinutes) private var focusMinutes
    @Default(.pomodoroBreakMinutes) private var breakMinutes
    @Default(.pomodoroAutoStartNextSession) private var autoStartNextSession
    @Default(.pomodoroShowLiveActivity) private var showLiveActivity
    @Default(.pomodoroNotificationsEnabled) private var notificationsEnabled

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .pomodoroEnabled) {
                    Text(AppL10n.text("Enable focus timer"))
                }
            } header: {
                Text(AppL10n.text("Focus Timer"))
            } footer: {
                Text(AppL10n.text("Adds a timer tab to the notch."))
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(value: $focusMinutes, in: 5...90, step: 5) {
                    HStack {
                        Text(AppL10n.text("Focus duration"))
                        Spacer()
                        Text(AppL10n.format("%lld min", focusMinutes))
                            .foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $breakMinutes, in: 1...30, step: 1) {
                    HStack {
                        Text(AppL10n.text("Break duration"))
                        Spacer()
                        Text(AppL10n.format("%lld min", breakMinutes))
                            .foregroundStyle(.secondary)
                    }
                }
                Defaults.Toggle(key: .pomodoroAutoStartNextSession) {
                    Text(AppL10n.text("Automatically start the next session"))
                }
            } header: {
                Text(AppL10n.text("Timing"))
            } footer: {
                Text(AppL10n.text("Changing a duration resets the current session when the timer is paused."))
                    .foregroundStyle(.secondary)
            }
            .disabled(!pomodoroEnabled)

            Section {
                Defaults.Toggle(key: .pomodoroShowLiveActivity) {
                    Text(AppL10n.text("Show countdown in the closed notch"))
                }
                Defaults.Toggle(key: .pomodoroNotificationsEnabled) {
                    Text(AppL10n.text("Notify when a session ends"))
                }
            } header: {
                Text(AppL10n.text("Feedback"))
            }
            .disabled(!pomodoroEnabled)

            Section {
                HStack {
                    Text(AppL10n.text("Completed focus sessions"))
                    Spacer()
                    Text("\(timer.completedFocusSessions)")
                        .foregroundStyle(.secondary)
                }
                Button(AppL10n.text("Reset timer and session count")) {
                    timer.restartCycle()
                }
                .disabled(!pomodoroEnabled)
            }
        }
        .navigationTitle(AppL10n.text("Focus Timer"))
        .onChange(of: focusMinutes) {
            timer.configurationDidChange()
        }
        .onChange(of: breakMinutes) {
            timer.configurationDidChange()
        }
        .onChange(of: pomodoroEnabled) {
            if !pomodoroEnabled {
                timer.pause()
                if coordinator.currentView == .pomodoro {
                    coordinator.currentView = .home
                }
            }
        }
    }
}

struct PomodoroView_Previews: PreviewProvider {
    static var previews: some View {
        PomodoroView()
            .environmentObject(BoringViewModel())
            .frame(width: 600, height: 130)
            .background(.black)
            .preferredColorScheme(.dark)
    }
}
