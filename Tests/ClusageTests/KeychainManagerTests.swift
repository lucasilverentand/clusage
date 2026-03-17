import Testing
import Foundation
@testable import Clusage

@Suite("KeychainManager")
struct KeychainManagerTests {
    @Test("Parses claudeAiOauth JSON with refresh token")
    func parsesOAuthWithRefresh() throws {
        let json = """
        {
            "claudeAiOauth": {
                "accessToken": "test-access",
                "refreshToken": "test-refresh",
                "expiresAt": 1710000000000
            }
        }
        """
        let data = json.data(using: .utf8)!
        let credential = KeychainManager.parseClaudeCodeCredential(data: data, serviceName: "test-service")

        #expect(credential != nil)
        #expect(credential?.accessToken == "test-access")
        #expect(credential?.refreshToken == "test-refresh")
        #expect(credential?.expiresAt != nil)
        #expect(credential?.serviceName == "test-service")
    }

    @Test("Parses claudeAiOauth JSON without refresh token")
    func parsesOAuthWithoutRefresh() throws {
        let json = """
        {
            "claudeAiOauth": {
                "accessToken": "just-access"
            }
        }
        """
        let data = json.data(using: .utf8)!
        let credential = KeychainManager.parseClaudeCodeCredential(data: data, serviceName: "svc")

        #expect(credential != nil)
        #expect(credential?.accessToken == "just-access")
        #expect(credential?.refreshToken == nil)
        #expect(credential?.expiresAt == nil)
    }

    @Test("Parses flat accessToken JSON")
    func parsesFlatAccessToken() throws {
        let json = """
        { "accessToken": "flat-token-123" }
        """
        let data = json.data(using: .utf8)!
        let credential = KeychainManager.parseClaudeCodeCredential(data: data, serviceName: "flat-svc")

        #expect(credential != nil)
        #expect(credential?.accessToken == "flat-token-123")
    }

    @Test("Parses flat access_token JSON (snake_case)")
    func parsesFlatSnakeCaseToken() throws {
        let json = """
        { "access_token": "snake-token" }
        """
        let data = json.data(using: .utf8)!
        let credential = KeychainManager.parseClaudeCodeCredential(data: data, serviceName: "snake-svc")

        #expect(credential != nil)
        #expect(credential?.accessToken == "snake-token")
    }

    @Test("Parses plain text token")
    func parsesPlainToken() throws {
        let data = "plain-text-token\n".data(using: .utf8)!
        let credential = KeychainManager.parseClaudeCodeCredential(data: data, serviceName: "plain-svc")

        #expect(credential != nil)
        #expect(credential?.accessToken == "plain-text-token")
    }

    @Test("Returns nil for empty data")
    func emptyData() {
        let data = "  \n  ".data(using: .utf8)!
        let credential = KeychainManager.parseClaudeCodeCredential(data: data, serviceName: "empty-svc")
        #expect(credential == nil)
    }

    @Test("Returns nil for JSON without token fields")
    func noTokenFields() {
        let json = """
        { "something": "else" }
        """
        let data = json.data(using: .utf8)!
        let credential = KeychainManager.parseClaudeCodeCredential(data: data, serviceName: "no-token-svc")
        #expect(credential == nil)
    }
}
