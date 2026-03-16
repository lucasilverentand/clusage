import Testing
import Foundation
@testable import Clusage

@Suite("APIClient")
struct APIClientTests {
    @Test("Decodes usage response")
    func decodesUsageResponse() throws {
        let json = """
        {
            "five_hour": { "utilization": 0.42, "resets_at": "2025-06-01T12:00:00.000Z" },
            "seven_day": { "utilization": 0.15, "resets_at": "2025-06-07T00:00:00.000Z" }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(UsageResponse.self, from: data)

        #expect(response.fiveHour.utilization == 0.42)
        #expect(response.sevenDay.utilization == 0.15)
        #expect(response.fiveHour.resetsAt == "2025-06-01T12:00:00.000Z")
    }

    @Test("Rate limited error is retryable")
    func rateLimitedIsRetryable() {
        let error = APIError.rateLimited(retryAfter: 10)
        #expect(error.isRetryable)
    }

    @Test("401 error is not retryable")
    func unauthorizedNotRetryable() {
        let error = APIError.httpError(statusCode: 401, body: nil)
        #expect(!error.isRetryable)
    }

    @Test("500 error is retryable")
    func serverErrorIsRetryable() {
        let error = APIError.httpError(statusCode: 500, body: nil)
        #expect(error.isRetryable)
    }

    @Test("Decodes profile response")
    func decodesProfileResponse() throws {
        let json = """
        {
            "account": {
                "full_name": "Test User",
                "display_name": "test",
                "email": "test@example.com"
            },
            "organization": {
                "name": "Test Org",
                "organization_type": "personal",
                "rate_limit_tier": "tier_1"
            }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(ProfileResponse.self, from: data)

        #expect(response.account.email == "test@example.com")
    }
}
