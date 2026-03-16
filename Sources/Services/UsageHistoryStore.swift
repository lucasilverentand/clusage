import Foundation

struct MonitoringGap: Codable, Identifiable, Sendable {
    let id: UUID
    let start: Date
    let end: Date

    init(start: Date, end: Date) {
        self.id = UUID()
        self.start = start
        self.end = end
    }
}

@Observable
@MainActor final class UsageHistoryStore {
    private(set) var snapshots: [UsageSnapshot] = []
    private(set) var gaps: [MonitoringGap] = []

    private let fileURL: URL
    private let gapsFileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("Clusage", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("usage-history.json")
        self.gapsFileURL = directory.appendingPathComponent("monitoring-gaps.json")
        loadSnapshots()
        loadGaps()
    }

    private var addCount = 0

    func addSnapshot(_ snapshot: UsageSnapshot) {
        // Deduplicate: skip if the most recent snapshot for this account
        // has the same values and was recorded less than 45 seconds ago
        if let last = snapshots.reversed().first(where: { $0.accountID == snapshot.accountID }),
           snapshot.timestamp.timeIntervalSince(last.timestamp) < 45,
           abs(snapshot.fiveHourUtilization - last.fiveHourUtilization) < 0.01,
           abs(snapshot.sevenDayUtilization - last.sevenDayUtilization) < 0.01
        {
            return
        }
        snapshots.append(snapshot)
        addCount += 1
        if addCount % 100 == 0 {
            prune()
        }
    }

    func snapshots(for accountID: UUID) -> [UsageSnapshot] {
        snapshots.filter { $0.accountID == accountID }
    }

    /// Remove snapshots older than 30 days.
    private func prune() {
        let cutoff = Date.now.addingTimeInterval(-30 * 24 * 60 * 60)
        snapshots.removeAll { $0.timestamp < cutoff }
        gaps.removeAll { $0.end < cutoff }
    }

    // MARK: - Gaps

    func addGap(_ gap: MonitoringGap) {
        // Only record gaps longer than 2 minutes (ignore brief blips)
        guard gap.end.timeIntervalSince(gap.start) > 120 else { return }
        // Deduplicate: skip if an existing gap overlaps significantly (within 60s of start)
        let dominated = gaps.contains { existing in
            abs(existing.start.timeIntervalSince(gap.start)) < 60
                && abs(existing.end.timeIntervalSince(gap.end)) < 60
        }
        guard !dominated else { return }
        gaps.append(gap)
    }

    func saveGaps() {
        guard let data = try? JSONEncoder().encode(gaps) else { return }
        try? data.write(to: gapsFileURL, options: .atomic)
    }

    private func loadGaps() {
        guard let data = try? Data(contentsOf: gapsFileURL) else { return }
        gaps = (try? JSONDecoder().decode([MonitoringGap].self, from: data)) ?? []
    }

    func clearAll() {
        snapshots.removeAll()
        gaps.removeAll()
        save()
        saveGaps()
    }

    // MARK: - Persistence

    func save() {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func loadSnapshots() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        snapshots = (try? JSONDecoder().decode([UsageSnapshot].self, from: data)) ?? []
    }
}
