import Foundation

struct PollingSettings: Sendable {
    var activeInterval: TimeInterval = 120
    var normalInterval: TimeInterval = 300
    var idleInterval: TimeInterval = 600

    static let defaults = PollingSettings()

    private static let activeKey = DefaultsKeys.pollingActiveInterval
    private static let normalKey = DefaultsKeys.pollingNormalInterval
    private static let idleKey = DefaultsKeys.pollingIdleInterval
    private static let rateLimitEventsKey = DefaultsKeys.pollingRateLimitEvents

    static func load() -> PollingSettings {
        let ud = UserDefaults.standard
        var settings = PollingSettings()
        let active = ud.double(forKey: activeKey)
        if active > 0 { settings.activeInterval = min(max(active, 30), 300) }
        let normal = ud.double(forKey: normalKey)
        if normal > 0 { settings.normalInterval = min(max(normal, 60), 600) }
        let idle = ud.double(forKey: idleKey)
        if idle > 0 { settings.idleInterval = min(max(idle, 120), 1800) }
        return settings
    }

    func save() {
        let ud = UserDefaults.standard
        ud.set(activeInterval, forKey: Self.activeKey)
        ud.set(normalInterval, forKey: Self.normalKey)
        ud.set(idleInterval, forKey: Self.idleKey)
    }

    // MARK: - Rate-Limit Tracking

    static func recordRateLimitEvent() {
        var events = loadRateLimitEvents()
        events.append(Date().timeIntervalSince1970)
        UserDefaults.standard.set(events, forKey: rateLimitEventsKey)
    }

    static func adaptiveMultiplier() -> Double {
        var events = loadRateLimitEvents()
        let now = Date().timeIntervalSince1970
        let twentyFourHoursAgo = now - TimeConstants.day

        // Prune events older than 24h
        events.removeAll { $0 < twentyFourHoursAgo }

        if events.isEmpty {
            clearRateLimitHistory()
            return 1.0
        }

        // Persist pruned list
        UserDefaults.standard.set(events, forKey: rateLimitEventsKey)

        // 3+ events in the last hour → scale up
        let oneHourAgo = now - TimeConstants.hour
        let recentCount = events.filter { $0 >= oneHourAgo }.count
        return recentCount >= 3 ? 1.5 : 1.0
    }

    static func clearRateLimitHistory() {
        UserDefaults.standard.removeObject(forKey: rateLimitEventsKey)
    }

    static func resetToDefaults() {
        let ud = UserDefaults.standard
        ud.removeObject(forKey: activeKey)
        ud.removeObject(forKey: normalKey)
        ud.removeObject(forKey: idleKey)
        clearRateLimitHistory()
    }

    private static func loadRateLimitEvents() -> [TimeInterval] {
        UserDefaults.standard.array(forKey: rateLimitEventsKey) as? [TimeInterval] ?? []
    }
}
