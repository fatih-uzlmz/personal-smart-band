import Foundation

/// A phone-local JSON store with no account or network dependency.
/// The host app must pass an Application Support URL outside iCloud Drive.
/// Scores and activity sessions live in sibling files next to the metrics file.
public struct LocalMetricStore {
    public let fileURL: URL

    private var scoresURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("scores.json")
    }

    private var sessionsURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("sessions.json")
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    // MARK: - Daily records

    public func load() throws -> [DailyRecord] {
        try read(fileURL)
    }

    public func upsert(_ incoming: DailyRecord) throws {
        var records = try load()
        if let index = records.firstIndex(where: {
            $0.deviceID == incoming.deviceID && $0.date == incoming.date
        }) {
            if let steps = incoming.steps { records[index].steps = steps }
            if let calories = incoming.vendorCaloriesKcal {
                records[index].vendorCaloriesKcal = calories
            }
            if !incoming.sleepSessions.isEmpty {
                records[index].sleepSessions = incoming.sleepSessions
            }
        } else {
            records.append(incoming)
        }
        records.sort { ($0.date, $0.deviceID) < ($1.date, $1.deviceID) }
        try write(records, to: fileURL)
    }

    // MARK: - Daily scores

    public func loadScores() throws -> [DailyScores] {
        try read(scoresURL)
    }

    public func saveScore(_ score: DailyScores) throws {
        var scores = try loadScores()
        if let index = scores.firstIndex(where: {
            $0.deviceID == score.deviceID && $0.date == score.date
        }) {
            scores[index] = score
        } else {
            scores.append(score)
        }
        scores.sort { ($0.date, $0.deviceID) < ($1.date, $1.deviceID) }
        try write(scores, to: scoresURL)
    }

    // MARK: - Activity sessions

    public func loadSessions() throws -> [ActivitySession] {
        try read(sessionsURL)
    }

    public func saveSession(_ session: ActivitySession) throws {
        var sessions = try loadSessions()
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        sessions.sort { ($0.date, $0.start) < ($1.date, $1.start) }
        try write(sessions, to: sessionsURL)
    }

    // MARK: - Private IO

    private func read<T: Decodable>(_ url: URL) throws -> [T] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([T].self, from: Data(contentsOf: url))
    }

    private func write<T: Encodable>(_ value: [T], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        var data = try JSONEncoder().encode(value)
        defer { data.resetBytes(in: 0..<data.count) }
        try data.write(to: url, options: .atomic)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                              ofItemAtPath: url.path)
        #endif
    }
}
