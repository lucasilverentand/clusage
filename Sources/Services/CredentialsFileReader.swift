import Foundation

/// Reads Claude Code credentials from `~/.claude/.credentials.json`.
/// This file is written by Claude Code and contains OAuth tokens directly,
/// avoiding the need for keychain access.
enum CredentialsFileReader {
    /// Sentinel service name used to identify file-sourced credentials.
    static let serviceName = "credentials-file"

    static let defaultPath = "~/.claude/.credentials.json"

    /// Read the credentials file and return a detected credential if valid.
    /// - Parameter customPath: Optional path override. Supports `~` expansion. Defaults to `~/.claude/.credentials.json`.
    static func read(path customPath: String? = nil) -> DetectedCredential? {
        let resolved: URL
        if let customPath, !customPath.isEmpty {
            let expanded = NSString(string: customPath).expandingTildeInPath
            resolved = URL(fileURLWithPath: expanded)
        } else {
            resolved = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/.credentials.json")
        }

        guard let data = try? Data(contentsOf: resolved) else {
            Log.keychain.debug("No credentials file at \(resolved.path)")
            return nil
        }

        return parse(data)
    }

    /// Parse credentials JSON data. Exposed for testability.
    static func parse(_ data: Data) -> DetectedCredential? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Log.keychain.warning("Credentials file is not valid JSON")
            return nil
        }

        guard let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String,
              !accessToken.isEmpty else {
            Log.keychain.debug("No claudeAiOauth.accessToken in credentials file")
            return nil
        }

        let refreshToken = oauth["refreshToken"] as? String

        var expiresAt: Date?
        if let expiresAtMs = oauth["expiresAt"] as? Double {
            expiresAt = Date(timeIntervalSince1970: expiresAtMs / 1000)
        }

        Log.keychain.info("Read credential from file (token length: \(accessToken.count), hasRefresh: \(refreshToken != nil))")
        return DetectedCredential(
            serviceName: serviceName,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )
    }
}
