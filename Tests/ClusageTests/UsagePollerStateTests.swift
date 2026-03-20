import Testing
import Foundation
@testable import Clusage

@Suite("UsagePoller State Transitions")
@MainActor
struct UsagePollerStateTests {
    private func makePoller(claudeRunning: Bool = true) -> UsagePoller {
        let accountStore = AccountStore()
        let historyStore = UsageHistoryStore()
        let poller = UsagePoller(
            accountStore: accountStore,
            historyStore: historyStore
        )
        poller.claudeIsRunning = claudeRunning
        return poller
    }

    /// Set explicit polling settings for tests and return a cleanup closure.
    private func setTestPollingSettings(
        active: TimeInterval = 120,
        normal: TimeInterval = 300,
        idle: TimeInterval = 600
    ) {
        var settings = PollingSettings(
            activeInterval: active,
            normalInterval: normal,
            idleInterval: idle
        )
        settings.save()
        PollingSettings.clearRateLimitHistory()
    }

    private func cleanUpPollingSettings() {
        PollingSettings.resetToDefaults()
    }

    // MARK: - Initial State

    @Test("Starts in normal state")
    func initialState() {
        let poller = makePoller()
        #expect(poller.pollState == .normal)
        #expect(poller.unchangedCycles == 0)
    }

    // MARK: - Normal -> Active

    @Test("Usage change transitions normal to active")
    func normalToActive() {
        let poller = makePoller()
        poller.pollState = .normal

        poller.updatePollState(usageChanged: true)

        #expect(poller.pollState == .active)
        #expect(poller.unchangedCycles == 0)
    }

    // MARK: - Active -> Normal (single unchanged cycle)

    @Test("Active drops to normal after one unchanged cycle")
    func activeToNormal() {
        let poller = makePoller()
        poller.pollState = .active

        poller.updatePollState(usageChanged: false)

        #expect(poller.pollState == .normal)
        #expect(poller.unchangedCycles == 1)
    }

    // MARK: - Normal stays Normal until idle threshold (Claude running)

    @Test("Normal stays normal while unchanged cycles below threshold (Claude running)")
    func normalStaysNormal() {
        let poller = makePoller(claudeRunning: true)
        poller.pollState = .normal
        poller.unchangedCycles = 0

        poller.updatePollState(usageChanged: false)
        #expect(poller.pollState == .normal)
        #expect(poller.unchangedCycles == 1)

        poller.updatePollState(usageChanged: false)
        #expect(poller.pollState == .normal)
        #expect(poller.unchangedCycles == 2)
    }

    // MARK: - Normal -> Idle at threshold (Claude running, threshold = 3)

    @Test("Normal transitions to idle at threshold when Claude is running")
    func normalToIdleClaudeRunning() {
        let poller = makePoller(claudeRunning: true)
        poller.pollState = .normal
        poller.unchangedCycles = 2  // one below threshold of 3

        poller.updatePollState(usageChanged: false)

        #expect(poller.pollState == .idle)
        #expect(poller.unchangedCycles == 3)
    }

    // MARK: - Normal -> Idle fast (no Claude, threshold = 1)

    @Test("Normal transitions to idle after 1 cycle when Claude is not running")
    func normalToIdleNoClaude() {
        let poller = makePoller(claudeRunning: false)
        poller.pollState = .normal
        poller.unchangedCycles = 0

        poller.updatePollState(usageChanged: false)

        #expect(poller.pollState == .idle)
        #expect(poller.unchangedCycles == 1)
    }

    // MARK: - Idle stays Idle

    @Test("Idle stays idle on continued inactivity")
    func idleStaysIdle() {
        let poller = makePoller()
        poller.pollState = .idle
        poller.unchangedCycles = 5

        poller.updatePollState(usageChanged: false)

        #expect(poller.pollState == .idle)
        #expect(poller.unchangedCycles == 6)
    }

    // MARK: - Idle -> Active (usage resumes)

    @Test("Idle transitions to active when usage resumes")
    func idleToActive() {
        let poller = makePoller()
        poller.pollState = .idle
        poller.unchangedCycles = 10

        poller.updatePollState(usageChanged: true)

        #expect(poller.pollState == .active)
        #expect(poller.unchangedCycles == 0)
    }

    // MARK: - Full cycle: Active -> Normal -> Idle -> Active (Claude running)

    @Test("Full lifecycle with Claude running: active -> normal -> idle -> active")
    func fullLifecycleClaudeRunning() {
        let poller = makePoller(claudeRunning: true)

        // Start: usage changing
        poller.updatePollState(usageChanged: true)
        #expect(poller.pollState == .active)

        // Usage stops — active drops to normal
        poller.updatePollState(usageChanged: false)
        #expect(poller.pollState == .normal)

        // 2 more unchanged cycles to reach threshold (3 total)
        poller.updatePollState(usageChanged: false)
        #expect(poller.pollState == .normal)
        poller.updatePollState(usageChanged: false)
        #expect(poller.pollState == .idle)

        // Stay idle
        poller.updatePollState(usageChanged: false)
        #expect(poller.pollState == .idle)

        // Usage resumes
        poller.updatePollState(usageChanged: true)
        #expect(poller.pollState == .active)
        #expect(poller.unchangedCycles == 0)
    }

    // MARK: - Full cycle: Active -> Normal -> Idle (fast, no Claude)

    @Test("Full lifecycle without Claude: active -> normal -> idle after 1 unchanged")
    func fullLifecycleNoClaude() {
        let poller = makePoller(claudeRunning: false)

        // Start: usage changing
        poller.updatePollState(usageChanged: true)
        #expect(poller.pollState == .active)

        // Usage stops — goes to normal, then idle immediately (threshold = 1)
        poller.updatePollState(usageChanged: false)
        #expect(poller.pollState == .idle)
    }

    // MARK: - Interval values

    @Test("Each state maps to the correct polling interval")
    func intervalValues() {
        setTestPollingSettings()
        defer { cleanUpPollingSettings() }

        let poller = makePoller()

        poller.pollState = .active
        #expect(poller.currentIntervalForTesting == 120)

        poller.pollState = .normal
        #expect(poller.currentIntervalForTesting == 300)

        poller.pollState = .idle
        #expect(poller.currentIntervalForTesting == 600)

        poller.pollState = .rateLimited
        #expect(poller.currentIntervalForTesting == 900)

        poller.pollState = .paused
        #expect(poller.currentIntervalForTesting == .infinity)
    }

    // MARK: - Rate Limited state

    @Test("Rate-limited state is set externally and updatePollState doesn't override it")
    func rateLimitedNotOverridden() {
        let poller = makePoller()
        poller.pollState = .rateLimited

        poller.unchangedCycles = 5
        poller.updatePollState(usageChanged: false)

        #expect(poller.pollState == .idle)
    }

    @Test("Rate-limited recovery: transitions to normal then follows usage")
    func rateLimitedRecovery() {
        let poller = makePoller(claudeRunning: true)
        poller.pollState = .rateLimited
        poller.unchangedCycles = 0

        poller.pollState = .normal
        poller.unchangedCycles = 0
        poller.updatePollState(usageChanged: false)

        #expect(poller.pollState == .normal)
        #expect(poller.unchangedCycles == 1)
    }

    @Test("Rate-limited recovery with usage change goes to active")
    func rateLimitedRecoveryWithChange() {
        let poller = makePoller()
        poller.pollState = .rateLimited

        poller.pollState = .normal
        poller.unchangedCycles = 0
        poller.updatePollState(usageChanged: true)

        #expect(poller.pollState == .active)
    }

    // MARK: - Claude detection affects threshold

    @Test("Claude starts running mid-session: idle threshold increases")
    func claudeStartsMidSession() {
        let poller = makePoller(claudeRunning: false)
        poller.pollState = .normal
        poller.unchangedCycles = 0

        poller.updatePollState(usageChanged: false)
        #expect(poller.pollState == .idle)

        poller.updatePollState(usageChanged: true)
        #expect(poller.pollState == .active)

        poller.claudeIsRunning = true

        poller.updatePollState(usageChanged: false)
        #expect(poller.pollState == .normal)

        poller.updatePollState(usageChanged: false)
        #expect(poller.pollState == .normal)

        poller.updatePollState(usageChanged: false)
        #expect(poller.pollState == .idle)
    }

    // MARK: - Adaptive Scaling

    @Test("Adaptive scaling multiplies intervals after 3 rate-limit events")
    func adaptiveScalingMultipliesIntervals() {
        setTestPollingSettings()
        defer { cleanUpPollingSettings() }

        // Record 3 rate-limit events
        PollingSettings.recordRateLimitEvent()
        PollingSettings.recordRateLimitEvent()
        PollingSettings.recordRateLimitEvent()

        #expect(PollingSettings.adaptiveMultiplier() == 1.5)

        let poller = makePoller()

        poller.pollState = .active
        #expect(poller.currentIntervalForTesting == 180) // 120 * 1.5

        poller.pollState = .normal
        #expect(poller.currentIntervalForTesting == 450) // 300 * 1.5

        poller.pollState = .idle
        #expect(poller.currentIntervalForTesting == 900) // 600 * 1.5
    }

    @Test("Adaptive scaling resets when events are older than 24h")
    func adaptiveScalingResetsAfter24h() {
        defer { cleanUpPollingSettings() }

        // Write old events directly (25 hours ago)
        let oldTimestamp = Date().timeIntervalSince1970 - 90000
        UserDefaults.standard.set(
            [oldTimestamp, oldTimestamp + 1, oldTimestamp + 2],
            forKey: DefaultsKeys.pollingRateLimitEvents
        )

        #expect(PollingSettings.adaptiveMultiplier() == 1.0)
    }
}
