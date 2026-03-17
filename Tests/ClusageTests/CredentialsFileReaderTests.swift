import Testing
import Foundation
@testable import Clusage

@Suite("CredentialsFileReader")
struct CredentialsFileReaderTests {
    @Test("Parses full claudeAiOauth credential")
    func parsesFullCredential() throws {
        let json = """
        {
            "claudeAiOauth": {
                "accessToken": "test-access-token-123",
                "refreshToken": "test-refresh-token-456",
                "expiresAt": 1710000000000
            }
        }
        """
        let data = json.data(using: .utf8)!
        let credential = CredentialsFileReader.parse(data)

        #expect(credential != nil)
        #expect(credential?.accessToken == "test-access-token-123")
        #expect(credential?.refreshToken == "test-refresh-token-456")
        #expect(credential?.expiresAt != nil)
        #expect(credential?.serviceName == CredentialsFileReader.serviceName)

        // expiresAt should be March 9, 2024 (1710000000 seconds since epoch)
        let expectedDate = Date(timeIntervalSince1970: 1_710_000_000)
        #expect(abs(credential!.expiresAt!.timeIntervalSince(expectedDate)) < 1)
    }

    @Test("Parses credential without refresh token")
    func parsesWithoutRefreshToken() throws {
        let json = """
        {
            "claudeAiOauth": {
                "accessToken": "token-only"
            }
        }
        """
        let data = json.data(using: .utf8)!
        let credential = CredentialsFileReader.parse(data)

        #expect(credential != nil)
        #expect(credential?.accessToken == "token-only")
        #expect(credential?.refreshToken == nil)
        #expect(credential?.expiresAt == nil)
    }

    @Test("Returns nil for missing claudeAiOauth key")
    func missingOAuthKey() {
        let json = """
        { "someOtherKey": { "token": "abc" } }
        """
        let data = json.data(using: .utf8)!
        #expect(CredentialsFileReader.parse(data) == nil)
    }

    @Test("Returns nil for missing accessToken")
    func missingAccessToken() {
        let json = """
        {
            "claudeAiOauth": {
                "refreshToken": "refresh-only"
            }
        }
        """
        let data = json.data(using: .utf8)!
        #expect(CredentialsFileReader.parse(data) == nil)
    }

    @Test("Returns nil for empty accessToken")
    func emptyAccessToken() {
        let json = """
        {
            "claudeAiOauth": {
                "accessToken": ""
            }
        }
        """
        let data = json.data(using: .utf8)!
        #expect(CredentialsFileReader.parse(data) == nil)
    }

    @Test("Returns nil for invalid JSON")
    func invalidJSON() {
        let data = "not json at all".data(using: .utf8)!
        #expect(CredentialsFileReader.parse(data) == nil)
    }
}
