import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let accountStore: AccountStore
    var momentumProvider: MomentumProvider?
    var historyStore: UsageHistoryStore?
    var streakStore: StreakStore?
    var poller: UsagePoller?

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showingResetData = false
    @State private var showingFullReset = false
    @State private var pollingSettings = PollingSettings.load()

    @Environment(\.openURL) private var openURL

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        Form {
            // MARK: - General

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            Log.app.error("Failed to \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)")
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            // MARK: - Polling

            Section {
                Stepper(
                    "Active: \(Formatting.settingsDuration(pollingSettings.activeInterval))",
                    value: $pollingSettings.activeInterval,
                    in: 30...300,
                    step: 30
                )
                .onChange(of: pollingSettings.activeInterval) { _, _ in pollingSettings.save() }

                Stepper(
                    "Normal: \(Formatting.settingsDuration(pollingSettings.normalInterval))",
                    value: $pollingSettings.normalInterval,
                    in: 60...600,
                    step: 60
                )
                .onChange(of: pollingSettings.normalInterval) { _, _ in pollingSettings.save() }

                Stepper(
                    "Idle: \(Formatting.settingsDuration(pollingSettings.idleInterval))",
                    value: $pollingSettings.idleInterval,
                    in: 120...1800,
                    step: 60
                )
                .onChange(of: pollingSettings.idleInterval) { _, _ in pollingSettings.save() }

                if PollingSettings.adaptiveMultiplier() > 1.0 {
                    Label("Intervals scaled 1.5× due to frequent rate limits", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Warning: intervals scaled 1.5 times due to frequent rate limits")
                }

                HStack {
                    Text("Intervals scale by 1.5× when rate limits are frequent.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset to Defaults") {
                        PollingSettings.resetToDefaults()
                        pollingSettings = PollingSettings.defaults
                    }
                    .font(.caption)
                }
            } header: {
                Text("Polling")
            }

            // MARK: - Data

            Section("Data") {
                LabeledContent("Snapshots", value: "\(historyStore?.snapshots.count ?? 0)")
                LabeledContent("Monitoring Gaps", value: "\(historyStore?.gaps.count ?? 0)")
                LabeledContent("Accounts", value: "\(accountStore.accounts.count)")
                if let provider = momentumProvider {
                    LabeledContent("Calibration Observations", value: "\(provider.ratioCalibrationStore.observations.count)")
                }
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset Usage Data")
                        Text("Clears snapshots, gaps, streaks, and projections. Keeps accounts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset Data") {
                        showingResetData = true
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Full Reset")
                        Text("Removes everything and returns the app to its initial state.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Full Reset", role: .destructive) {
                        showingFullReset = true
                    }
                }
            }

            // MARK: - About

            Section("About") {
                LabeledContent("Version", value: "\(appVersion) (\(buildNumber))")

                HStack(spacing: 16) {
                    Link("GitHub", destination: URL(string: "https://github.com/seventwo-studio/clusage")!)
                    Link("Sponsor", destination: URL(string: "https://github.com/sponsors/lucasilverentand")!)
                    Link("Report Issue", destination: URL(string: "https://github.com/seventwo-studio/clusage/issues/new")!)
                }
                .font(.callout)

                Text("Made by Luca Silverentand")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .navigationSubtitle("Preferences and data management")
        .toolbarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Reset all usage data?",
            isPresented: $showingResetData,
            titleVisibility: .visible
        ) {
            Button("Reset Data", role: .destructive) {
                resetUsageData()
            }
        } message: {
            Text("This will delete all snapshots, monitoring gaps, streaks, and calibration data. Your accounts will be kept.")
        }
        .confirmationDialog(
            "Completely reset Clusage?",
            isPresented: $showingFullReset,
            titleVisibility: .visible
        ) {
            Button("Full Reset", role: .destructive) {
                fullReset()
            }
        } message: {
            Text("This will delete all accounts, tokens, usage data, and settings. This cannot be undone.")
        }
    }

    // MARK: - Actions

    private func resetUsageData() {
        ResetService.resetUsageData(
            accountStore: accountStore,
            historyStore: historyStore,
            streakStore: streakStore,
            momentumProvider: momentumProvider
        )
    }

    private func fullReset() {
        ResetService.fullReset(
            accountStore: accountStore,
            historyStore: historyStore,
            streakStore: streakStore,
            momentumProvider: momentumProvider
        )
        pollingSettings = PollingSettings.defaults
    }
}
