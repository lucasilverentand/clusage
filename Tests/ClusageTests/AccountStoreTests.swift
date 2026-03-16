import Testing
import Foundation
@testable import Clusage

@Suite("AccountStore")
struct AccountStoreTests {
    @Test("Account has correct display name without profile")
    func displayNameWithoutProfile() {
        let account = Account(name: "My Account")
        #expect(account.displayName == "My Account")
    }

    @Test("Account has correct display name with profile")
    func displayNameWithProfile() {
        var account = Account(name: "My Account")
        account.profile = Profile(from: ProfileResponse(
            account: ProfileAccount(email: "test@example.com")
        ))
        #expect(account.displayName == "test@example.com")
    }

    @Test("Account encodes and decodes")
    func codable() throws {
        let account = Account(name: "Test")
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(Account.self, from: data)

        #expect(decoded.id == account.id)
        #expect(decoded.name == account.name)
    }
}
