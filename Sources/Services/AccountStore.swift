import Foundation
import Observation

@Observable
@MainActor final class AccountStore {
    private(set) var accounts: [Account] = []

    /// The account shown in the menu bar icon. Falls back to first account.
    var menuBarAccountID: UUID? {
        didSet { defaults.set(menuBarAccountID?.uuidString, forKey: menuBarAccountKey) }
    }

    var menuBarAccount: Account? {
        if let id = menuBarAccountID, let match = accounts.first(where: { $0.id == id }) {
            return match
        }
        return accounts.first
    }

    private let defaults = UserDefaults.standard
    private let storageKey = DefaultsKeys.accounts
    private let menuBarAccountKey = DefaultsKeys.menuBarAccountID
    /// In-memory token map loaded once from Keychain at init.
    private var tokens: [String: String] = [:]

    init() {
        loadAccounts()
        loadTokensFromKeychain()
        if let raw = defaults.string(forKey: menuBarAccountKey), let id = UUID(uuidString: raw) {
            menuBarAccountID = id
        }
    }

    func addAccount(name: String, token: String, profile: Profile? = nil, keychainServiceName: String? = nil) {
        var account = Account(name: name)
        account.profile = profile
        account.keychainServiceName = keychainServiceName
        Log.accounts.info("Adding account '\(name)' (\(account.id.uuidString))")
        tokens[account.id.uuidString] = token
        accounts.append(account)
        saveAccounts()
        _ = KeychainManager.saveToken(token, for: account.id)
        Log.accounts.info("Account added. Total accounts: \(self.accounts.count)")
    }

    func removeAccount(_ account: Account) {
        Log.accounts.info("Removing account '\(account.name)' (\(account.id.uuidString))")
        tokens.removeValue(forKey: account.id.uuidString)
        accounts.removeAll { $0.id == account.id }
        if menuBarAccountID == account.id {
            menuBarAccountID = accounts.first?.id
        }
        saveAccounts()
        KeychainManager.deleteToken(for: account.id)
        Log.accounts.info("Account removed. Total accounts: \(self.accounts.count)")
    }

    func moveAccounts(from source: IndexSet, to destination: Int) {
        accounts.move(fromOffsets: source, toOffset: destination)
        saveAccounts()
    }

    func updateAccount(_ account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            Log.accounts.warning("updateAccount called for unknown account \(account.id.uuidString)")
            return
        }
        accounts[index] = account
        saveAccounts()
    }

    func token(for account: Account) -> String? {
        tokens[account.id.uuidString]
    }

    /// Update the stored token for an account.
    func updateToken(_ token: String, for account: Account) {
        tokens[account.id.uuidString] = token
        _ = KeychainManager.saveToken(token, for: account.id)
    }

    /// The email associated with an account — checks profile first, falls back to name.
    func email(for account: Account) -> String? {
        if let email = account.profile?.email { return email }
        // The name is often the email (set during import)
        if account.name.contains("@") { return account.name }
        return nil
    }

    /// Refresh the token for an account from its bound keychain entry.
    /// Each account must have a `keychainServiceName` — this method only reads from that entry.
    /// Returns the new token if successfully refreshed, nil if the keychain entry is missing.
    func refreshTokenFromKeychain(for account: Account) -> String? {
        guard let serviceName = account.keychainServiceName else {
            Log.accounts.warning("[\(account.displayName)] No keychain binding — cannot refresh token")
            return nil
        }

        guard let credential = KeychainManager.fetchClaudeCodeCredential(serviceName: serviceName) else {
            Log.accounts.warning("[\(account.displayName)] Keychain entry '\(serviceName)' not found")
            return nil
        }

        let oldToken = tokens[account.id.uuidString]
        if credential.accessToken != oldToken {
            Log.accounts.info("[\(account.displayName)] Refreshed token from keychain '\(serviceName)'")
            tokens[account.id.uuidString] = credential.accessToken
            _ = KeychainManager.saveToken(credential.accessToken, for: account.id)
        } else {
            Log.accounts.debug("[\(account.displayName)] Keychain token unchanged")
        }
        return credential.accessToken
    }

    /// Refresh tokens from keychain for all accounts that have a keychain binding.
    /// Returns true if any tokens were refreshed.
    @discardableResult
    func refreshAllFromKeychain() -> Bool {
        let boundAccounts = accounts.filter { $0.keychainServiceName != nil }
        guard !boundAccounts.isEmpty else { return false }

        Log.accounts.info("Refreshing tokens from keychain for \(boundAccounts.count) bound account(s)")
        var refreshedAny = false

        for account in boundAccounts {
            let oldToken = tokens[account.id.uuidString]
            if let freshToken = refreshTokenFromKeychain(for: account),
               freshToken != oldToken {
                refreshedAny = true
            }
        }

        return refreshedAny
    }

    /// Re-link an account to a different keychain entry. Used when the original entry
    /// disappears or an email mismatch is detected.
    func relinkKeychain(for account: Account, credential: DetectedCredential) {
        guard let idx = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[idx].keychainServiceName = credential.serviceName
        accounts[idx].lastError = nil
        tokens[account.id.uuidString] = credential.accessToken
        saveAccounts()
        _ = KeychainManager.saveToken(credential.accessToken, for: account.id)
        Log.accounts.info("[\(account.displayName)] Re-linked to keychain '\(credential.serviceName)'")
    }

    // MARK: - Persistence

    private func loadAccounts() {
        guard let data = defaults.data(forKey: storageKey) else {
            Log.accounts.info("No saved accounts found in UserDefaults")
            return
        }
        do {
            accounts = try JSONDecoder().decode([Account].self, from: data)
            Log.accounts.info("Loaded \(self.accounts.count) account(s) from UserDefaults")
        } catch {
            Log.accounts.error("Failed to decode saved accounts: \(error.localizedDescription)")
            accounts = []
        }
    }

    private func saveAccounts() {
        guard let data = try? JSONEncoder().encode(accounts) else {
            Log.accounts.error("Failed to encode accounts for saving")
            return
        }
        defaults.set(data, forKey: storageKey)
        Log.accounts.debug("Saved \(self.accounts.count) account(s) to UserDefaults")
    }

    /// Load each account's token from the Keychain into the in-memory cache.
    private func loadTokensFromKeychain() {
        tokens = [:]
        for account in accounts {
            if let token = KeychainManager.loadToken(for: account.id) {
                tokens[account.id.uuidString] = token
            }
        }
        if !tokens.isEmpty {
            Log.accounts.info("Loaded \(self.tokens.count) token(s) from Keychain")
        }
    }

}
