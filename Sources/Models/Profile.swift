import Foundation

struct Profile: Codable, Sendable {
    let email: String

    init(email: String) {
        self.email = email
    }

    init(from response: ProfileResponse) {
        self.email = response.account.email
    }
}
