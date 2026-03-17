import Foundation

struct Account: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var fiveHour: UsageWindow?
    var sevenDay: UsageWindow?
    var profile: Profile?
    var lastUpdated: Date?
    var lastError: String?
    /// The keychain service name this account was imported from (e.g. "Claude Code-credentials-...").
    /// Used to re-read fresh tokens when the stored one expires.
    var keychainServiceName: String?
    /// When the current access token expires (used for proactive refresh).
    var tokenExpiresAt: Date?
    /// Custom path to a `.credentials.json` file for this account.
    /// When nil, defaults to `~/.claude/.credentials.json`.
    var credentialsFilePath: String?
    /// Per-account usage schedule.
    var usagePlan: UsagePlan = UsagePlan()

    var displayName: String {
        if let profile {
            return profile.email
        }
        return name
    }

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}
