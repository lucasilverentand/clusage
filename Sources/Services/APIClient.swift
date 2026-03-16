import Foundation

actor APIClient {
    static let shared = APIClient()

    private let baseURL = URL(string: "https://api.anthropic.com/api/oauth")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchUsage(token: String) async throws -> UsageResponse {
        let url = baseURL.appendingPathComponent("usage")
        Log.api.debug("Fetching usage from \(url.absoluteString)")
        let (data, _) = try await perform(request: makeRequest(url: url, token: token))
        let response = try JSONDecoder().decode(UsageResponse.self, from: data)
        Log.api.info("Usage fetched — 5h: \(String(format: "%.1f%%", response.fiveHour.utilization)), 7d: \(String(format: "%.1f%%", response.sevenDay.utilization))")
        return response
    }

    func fetchProfile(token: String) async throws -> ProfileResponse {
        let url = baseURL.appendingPathComponent("profile")
        Log.api.debug("Fetching profile from \(url.absoluteString)")
        let (data, _) = try await perform(request: makeRequest(url: url, token: token))
        let response = try JSONDecoder().decode(ProfileResponse.self, from: data)
        Log.api.info("Profile fetched — \(response.account.email)")
        return response
    }

    /// Validates that a token works by hitting the usage endpoint.
    /// Returns the usage response on success so callers can use it immediately.
    func validateToken(_ token: String) async throws -> UsageResponse {
        Log.api.debug("Validating token (length: \(token.count))")
        return try await fetchUsage(token: token)
    }

    // MARK: - Private

    private func makeRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Clusage/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 15
        return request
    }

    private func perform(request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Log.api.error("Network error: \(error.localizedDescription)")
            throw error
        }

        guard let http = response as? HTTPURLResponse else {
            Log.api.error("Invalid response type (not HTTP)")
            throw APIError.invalidResponse
        }

        Log.api.debug("HTTP \(http.statusCode) from \(request.url?.absoluteString ?? "?")")

        if http.statusCode == 429 {
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            Log.api.warning("Rate limited (429). Retry-After: \(retryAfter.map { String(describing: $0) } ?? "none")")
            throw APIError.rateLimited(retryAfter: retryAfter)
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            Log.api.error("HTTP error \(http.statusCode): \(body ?? "<no body>")")
            throw APIError.httpError(statusCode: http.statusCode, body: body)
        }

        return (data, http)
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case rateLimited(retryAfter: Double?)
    case httpError(statusCode: Int, body: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from server."
        case .rateLimited:
            "Rate limited by Anthropic. Backing off."
        case .httpError(let code, _):
            switch code {
            case 401: "Invalid or expired token."
            case 403: "Access denied. Check your token permissions."
            default: "HTTP error \(code)."
            }
        }
    }

    var isRetryable: Bool {
        switch self {
        case .rateLimited: true
        case .httpError(let code, _): code >= 500
        default: false
        }
    }

    var isRateLimited: Bool {
        if case .rateLimited = self { return true }
        return false
    }

    var is401: Bool {
        if case .httpError(let code, _) = self { return code == 401 }
        return false
    }
}
