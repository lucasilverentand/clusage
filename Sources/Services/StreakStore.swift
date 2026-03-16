import Foundation

@Observable
@MainActor final class StreakStore {
    private(set) var streaks: [UUID: UsageStreak] = [:]

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("Clusage", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("streaks.json")
        loadStreaks()
    }

    func streak(for accountID: UUID) -> UsageStreak {
        streaks[accountID] ?? UsageStreak()
    }

    func update(_ streak: UsageStreak, for accountID: UUID) {
        streaks[accountID] = streak
    }

    func clearAll() {
        streaks.removeAll()
        save()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(streaks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func loadStreaks() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        streaks = (try? JSONDecoder().decode([UUID: UsageStreak].self, from: data)) ?? [:]
    }
}
