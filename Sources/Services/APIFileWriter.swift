import Foundation

/// Writes a JSON file to `~/.claude/clusage-api.json` that external tools
/// (e.g. ClaudeLine) can read for usage data without hitting the Anthropic API.
struct APIFileWriter {
    private static let fileName = "clusage-api.json"

    private static var fileURL: URL {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
        try? FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        return claudeDir.appendingPathComponent(fileName)
    }

    @MainActor func write(accounts: [Account], momentumProvider: MomentumProvider?) {
        let accountEntries = accounts.compactMap { account -> APIFileAccount? in
            guard let fiveHour = account.fiveHour, let sevenDay = account.sevenDay else {
                return nil
            }

            let momentum = momentumProvider?.momentum(for: account.id)
            let projection = momentumProvider?.projection(for: account.id)

            return APIFileAccount(
                id: account.id.uuidString,
                name: account.displayName,
                fiveHour: APIFileWindow(
                    utilization: fiveHour.utilization,
                    resetsAt: fiveHour.resetsAt
                ),
                sevenDay: APIFileWindow(
                    utilization: sevenDay.utilization,
                    resetsAt: sevenDay.resetsAt
                ),
                profile: account.profile.map { profile in
                    APIFileProfile(email: profile.email)
                },
                momentum: momentum.map { m in
                    APIFileMomentum(
                        velocity: m.velocity,
                        acceleration: m.acceleration,
                        intensity: m.intensity.rawValue,
                        etaToCeiling: m.etaToCeiling,
                        resetsFirst: m.resetsFirst
                    )
                },
                projection: projection.map { p in
                    APIFileProjection(
                        sevenDayVelocity: p.sevenDayVelocity,
                        projectedAtReset: p.projectedAtReset,
                        dailyBudget: p.dailyBudget,
                        dailyProjected: p.dailyProjected,
                        remainingDays: p.remainingDays,
                        status: p.status.rawValue,
                        granularSevenDayUtilization: p.currentGranularUtilization(),
                        usedCalibratedRatio: p.usedCalibratedRatio
                    )
                }
            )
        }

        let payload = APIFilePayload(
            version: 1,
            updatedAt: Date(),
            accounts: accountEntries
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(payload) else {
            Log.api.error("Failed to encode API file data")
            return
        }

        do {
            try data.write(to: Self.fileURL, options: .atomic)
            Log.api.debug("API file written (\(accountEntries.count) account(s), \(data.count) bytes)")
        } catch {
            Log.api.error("Failed to write API file: \(error.localizedDescription)")
        }
    }
}

// MARK: - JSON Schema

struct APIFilePayload: Codable {
    let version: Int
    let updatedAt: Date
    let accounts: [APIFileAccount]
}

struct APIFileAccount: Codable {
    let id: String
    let name: String
    let fiveHour: APIFileWindow
    let sevenDay: APIFileWindow
    let profile: APIFileProfile?
    let momentum: APIFileMomentum?
    let projection: APIFileProjection?
}

struct APIFileWindow: Codable {
    let utilization: Double
    let resetsAt: Date
}

struct APIFileProfile: Codable {
    let email: String
}

struct APIFileMomentum: Codable {
    let velocity: Double
    let acceleration: Double
    let intensity: String
    let etaToCeiling: Double?
    let resetsFirst: Bool
}

struct APIFileProjection: Codable {
    let sevenDayVelocity: Double
    let projectedAtReset: Double
    let dailyBudget: Double
    let dailyProjected: Double
    let remainingDays: Double
    let status: String
    let granularSevenDayUtilization: Double?
    let usedCalibratedRatio: Bool
}
