import SwiftUI

@main
struct BandApp: App {
    @StateObject private var model = DashboardModel()

    var body: some Scene {
        WindowGroup {
            DashboardView(model: model)
        }
    }
}

@MainActor
final class DashboardModel: ObservableObject {
    @Published private(set) var today: DailyRecord?
    @Published private(set) var todayScores: DailyScores?
    @Published private(set) var errorMessage: String?

    private let store: LocalMetricStore

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask)[0]
        store = LocalMetricStore(fileURL: directory.appendingPathComponent("Band/metrics.json"))
        reload()
    }

    private static let previewDeviceIDs: Set<String> = ["sample-preview", "mock-h7"]

    var isSample: Bool {
        guard let id = today?.deviceID else { return false }
        return Self.previewDeviceIDs.contains(id)
    }

    /// Loads a deterministic 7-day mock week through the same adapter path the
    /// real band client uses, plus one tagged soccer session. Pre-hardware
    /// testing only: the mock client never touches Bluetooth or the network.
    func loadMockWeek() async {
        do {
            let client = MockBandSyncClient()
            let records = try await client.sync()
            for record in records {
                try store.upsert(record)
            }
            for session in try client.mockSessions() {
                try store.saveSession(session)
            }
            reload()
        } catch {
            errorMessage = "Could not load mock week: \(error.localizedDescription)"
        }
    }

    func reload() {
        do {
            let date = Self.todayKey()
            let allRecords = try store.load()
            let records = allRecords.filter { $0.date == date }
            today = records.first(where: { !Self.previewDeviceIDs.contains($0.deviceID) })
                ?? records.first(where: { Self.previewDeviceIDs.contains($0.deviceID) })
            if let record = today {
                let scores = ScoreComputer.scores(for: record, history: allRecords)
                try? store.saveScore(scores)
                todayScores = scores
            } else {
                todayScores = nil
            }
            errorMessage = nil
        } catch {
            errorMessage = "Could not read local data: \(error.localizedDescription)"
        }
    }

    #if !targetEnvironment(simulator)
    @Published private(set) var syncStatus: String?

    /// Runs a full BLE sync against the H7 band and saves the results.
    func syncBand() async {
        syncStatus = "Looking for your band\u{2026}"
        errorMessage = nil
        do {
            let records = try await VeepooBandSyncClient().sync()
            for record in records {
                try store.upsert(record)
            }
            reload()
            syncStatus = "Synced \(records.count) days from the band."
        } catch {
            syncStatus = nil
            errorMessage = "Sync failed: \(error.localizedDescription)"
        }
    }
    #endif

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
