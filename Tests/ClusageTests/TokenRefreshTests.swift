import Testing
import Foundation
@testable import Clusage

@Suite("TokenRefresh")
struct TokenRefreshTests {
    @Test("Decodes token refresh response with all fields")
    func decodesFullResponse() throws {
        let json = """
        {
            "access_token": "new-access-token",
            "refresh_token": "new-refresh-token",
            "expires_in": 3600,
            "token_type": "bearer"
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(TokenRefreshResponse.self, from: data)

        #expect(response.accessToken == "new-access-token")
        #expect(response.refreshToken == "new-refresh-token")
        #expect(response.expiresIn == 3600)
        #expect(response.tokenType == "bearer")
    }

    @Test("Decodes token refresh response with minimal fields")
    func decodesMinimalResponse() throws {
        let json = """
        {
            "access_token": "just-a-token"
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(TokenRefreshResponse.self, from: data)

        #expect(response.accessToken == "just-a-token")
        #expect(response.refreshToken == nil)
        #expect(response.expiresIn == nil)
        #expect(response.tokenType == nil)
    }

    @Test("OAuth client ID is set correctly")
    func clientID() {
        #expect(APIClient.claudeOAuthClientID == "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
    }
}
