import Foundation

struct UsageResponse: Codable, Sendable {
    let fiveHour: UsageWindowResponse
    let sevenDay: UsageWindowResponse

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

struct UsageWindowResponse: Codable, Sendable {
    let utilization: Double
    let resetsAt: String

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct ProfileResponse: Codable, Sendable {
    let account: ProfileAccount
}

struct ProfileAccount: Codable, Sendable {
    let email: String
}

struct TokenRefreshResponse: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}
