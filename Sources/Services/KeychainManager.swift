import Foundation
import Security

/// A Claude Code credential found in the macOS Keychain.
struct DetectedCredential: Identifiable, Sendable {
    let id = UUID()
    let serviceName: String
    let accessToken: String
    /// Email fetched from the profile API (populated after detection).
    var email: String?

    /// Human-readable label derived from metadata.
    var label: String {
        email ?? serviceName
    }
}

/// Handles Claude Code credential detection from the system keychain.
/// Uses the `security` CLI to avoid Security framework prompts.
/// Token storage for Clusage accounts uses the macOS Keychain via the Security framework.
enum KeychainManager {

    // MARK: - Claude Code Detection

    /// Find all Claude Code credential entries using the `security` CLI to avoid keychain prompts.
    /// Runs the blocking Process calls off the main thread.
    static func detectAllClaudeCodeCredentials() async -> [DetectedCredential] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = detectAllClaudeCodeCredentialsSync()
                continuation.resume(returning: result)
            }
        }
    }

    /// Synchronous implementation — must be called off the main thread.
    private static func detectAllClaudeCodeCredentialsSync() -> [DetectedCredential] {
        Log.keychain.debug("Searching for Claude Code keychain items via security CLI")

        let serviceNames = findClaudeCodeServiceNames()
        guard !serviceNames.isEmpty else {
            Log.keychain.info("No Claude Code credentials found")
            return []
        }

        Log.keychain.debug("Found \(serviceNames.count) Claude Code service name(s)")

        var credentials: [DetectedCredential] = []
        for serviceName in serviceNames {
            if let cred = fetchClaudeCodeCredentialSync(serviceName: serviceName) {
                credentials.append(cred)
            }
        }

        Log.keychain.info("Found \(credentials.count) Claude Code credential(s)")
        return credentials
    }

    /// Use `security dump-keychain` to find service names matching Claude Code without prompting.
    private static func findClaudeCodeServiceNames() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["dump-keychain"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            Log.keychain.warning("Failed to run security CLI: \(error.localizedDescription)")
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var serviceNames = Set<String>()
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("0x00000007") && trimmed.contains("Claude Code-credentials") {
                if let start = trimmed.range(of: "=\""),
                   let end = trimmed.range(of: "\"", range: start.upperBound..<trimmed.endIndex) {
                    let name = String(trimmed[start.upperBound..<end.lowerBound])
                    serviceNames.insert(name)
                }
            }
        }

        return Array(serviceNames)
    }

    /// Fetch a single Claude Code credential by service name using `security find-generic-password`.
    /// Runs the blocking Process call off the main thread.
    static func fetchClaudeCodeCredential(serviceName: String) async -> DetectedCredential? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = fetchClaudeCodeCredentialSync(serviceName: serviceName)
                continuation.resume(returning: result)
            }
        }
    }

    /// Synchronous implementation — must be called off the main thread.
    private static func fetchClaudeCodeCredentialSync(serviceName: String) -> DetectedCredential? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", serviceName, "-w"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            Log.keychain.warning("Failed to read '\(serviceName)': \(error.localizedDescription)")
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            Log.keychain.warning("security CLI returned \(process.terminationStatus) for '\(serviceName)'")
            return nil
        }

        return parseClaudeCodeCredential(data: data, serviceName: serviceName)
    }

    private static func parseClaudeCodeCredential(data: Data, serviceName: String) -> DetectedCredential? {
        guard let raw = String(data: data, encoding: .utf8) else {
            Log.keychain.warning("Non-UTF8 data in '\(serviceName)'")
            return nil
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let jsonData = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            Log.keychain.debug("Parsed plain token from '\(serviceName)' (length: \(trimmed.count))")
            return DetectedCredential(serviceName: serviceName, accessToken: trimmed)
        }

        if let oauth = json["claudeAiOauth"] as? [String: Any],
           let accessToken = oauth["accessToken"] as? String {
            Log.keychain.debug("Parsed credential from '\(serviceName)' (token length: \(accessToken.count))")
            return DetectedCredential(serviceName: serviceName, accessToken: accessToken)
        }

        if let accessToken = json["accessToken"] as? String ?? json["access_token"] as? String {
            Log.keychain.debug("Parsed flat token from '\(serviceName)' (length: \(accessToken.count))")
            return DetectedCredential(serviceName: serviceName, accessToken: accessToken)
        }

        Log.keychain.warning("Failed to extract token from '\(serviceName)'")
        return nil
    }

    // MARK: - Clusage Token Storage

    private static let servicePrefix = "studio.seventwo.clusage.token."

    static func saveToken(_ token: String, for accountID: UUID) -> Bool {
        let service = servicePrefix + accountID.uuidString
        let data = Data(token.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
        ]

        // Try update first
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)

        if updateStatus == errSecSuccess {
            return true
        }

        // If not found, add new
        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        if addStatus != errSecSuccess {
            Log.keychain.error("Failed to save token for \(accountID.uuidString): OSStatus \(addStatus)")
        }
        return addStatus == errSecSuccess
    }

    static func loadToken(for accountID: UUID) -> String? {
        let service = servicePrefix + accountID.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteToken(for accountID: UUID) {
        let service = servicePrefix + accountID.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
