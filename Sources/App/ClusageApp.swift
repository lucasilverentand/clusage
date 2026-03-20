import AppKit
import SwiftUI

@main
struct ClusageApp: App {
    @State private var accountStore = AccountStore()
    @State private var historyStore = UsageHistoryStore()
    @State private var streakStore = StreakStore()
    @State private var momentumProvider: MomentumProvider?
    @State private var poller: UsagePoller?

    @State private var menuBarViewModel: MenuBarViewModel?
    @State private var dashboardViewModel: DashboardViewModel?
    @State private var terminationObserver: NSObjectProtocol?

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            if let menuBarViewModel {
                MenuBarView(viewModel: menuBarViewModel)
                    .onAppear {
                        Log.app.info("Menu bar popover appeared")
                        if accountStore.accounts.isEmpty {
                            Log.app.info("No accounts — opening dashboard for onboarding")
                            openWindow(id: "dashboard")
                        }
                    }
            }
        } label: {
            MenuBarIcon(accountStore: accountStore)
            .task {
                recordStartupGap()
                await accountStore.refreshAllFromKeychain()
                startPolling()
                observeAppLifecycle()
            }
        }
        .menuBarExtraStyle(.window)

        Window("Dashboard", id: "dashboard") {
            if let dashboardViewModel {
                DashboardView(viewModel: dashboardViewModel)
                    .onAppear {
                        Log.app.info("Dashboard window opened")
                        bringDashboardToFront()
                    }
            }
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(
                accountStore: accountStore,
                momentumProvider: momentumProvider,
                historyStore: historyStore,
                streakStore: streakStore,
                poller: poller
            )
            .frame(width: 480, height: 620)
        }
    }

    /// Bring the dashboard window to the front and activate the app.
    /// Uses NSWorkspace notification instead of DispatchQueue.main.async.
    private func bringDashboardToFront() {
        guard let window = NSApp.windows.first(where: { $0.title == "Dashboard" }) else { return }
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.center()
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate()
    }

    private func recordStartupGap() {
        let quitTimestamp = UserDefaults.standard.double(forKey: DefaultsKeys.lastQuitAt)
        guard quitTimestamp > 0 else {
            Log.app.info("App started — no previous quit time recorded (first launch)")
            return
        }
        let quitDate = Date(timeIntervalSince1970: quitTimestamp)
        let gap = MonitoringGap(start: quitDate, end: Date())
        historyStore.addGap(gap)
        historyStore.saveGaps()
        Log.app.info("App started — recorded gap since quit: \(String(format: "%.0f", Date().timeIntervalSince(quitDate)))s")
        // Remove quit key AND update lastPollAt so the poller doesn't record a duplicate gap
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.lastQuitAt)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: DefaultsKeys.lastPollAt)
    }

    private func observeAppLifecycle() {
        guard terminationObserver == nil else { return }
        let pollerRef = poller
        let historyRef = historyStore
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { _ in
            Log.app.info("App terminating — stopping poller and saving state")
            pollerRef?.stop()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: DefaultsKeys.lastQuitAt)
            historyRef.save()
            historyRef.saveGaps()
        }
    }

    private func startPolling() {
        guard poller == nil else { return }
        Log.app.info("Creating and starting poller")

        let provider = MomentumProvider(
            historyStore: historyStore,
            streakStore: streakStore,
            accountStore: accountStore
        )
        provider.refresh()
        momentumProvider = provider

        let newPoller = UsagePoller(
            accountStore: accountStore,
            historyStore: historyStore,
            momentumProvider: provider
        )
        poller = newPoller
        newPoller.start()

        // Create view models once, after services are initialized
        menuBarViewModel = MenuBarViewModel(
            accountStore: accountStore,
            poller: newPoller,
            momentumProvider: provider
        )
        dashboardViewModel = DashboardViewModel(
            accountStore: accountStore,
            historyStore: historyStore,
            streakStore: streakStore,
            momentumProvider: provider,
            poller: newPoller
        )
    }
}
