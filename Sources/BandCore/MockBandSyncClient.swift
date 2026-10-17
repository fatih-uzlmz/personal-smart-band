import Foundation

/// Deterministic mock band for pre-hardware development and UI testing.
///
/// Produces a 7-day week of plausible H7-style data through the SAME adapter
/// path as the real client: raw vendor-style dictionaries -> VeepooStepMapper
/// -> DailyRecord, with one sleep session per record for the night that ended
/// that morning. No Bluetooth, no network, no randomness beyond the fixed
/// seed: the same seed always yields the same week, so the dashboard, the
/// scoring engine, and the session store stay testable and demoable.
///
/// On hardware day, swap this for ``VeepooBandSyncClient`` (same
/// ``BandSyncClient`` protocol) — nothing downstream changes.
public struct MockBandSyncClient: BandSyncClient {
    public var displayName: String { "Mock H7" }

    public let deviceID: String
    public let days: Int
    private let seed: UInt64

    public init(deviceID: String = "mock-h7", days: Int = 7, seed: UInt64 = 42) {
        self.deviceID = deviceID
        self.days = days
        self.seed = seed
    }

    public func sync() async throws -> [DailyRecord] {
        var rng = LCGRandom(seed: seed)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var records: [DailyRecord] = []
        records.reserveCapacity(days)

        // Oldest day first so the result is chronological.
        for back in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            let isSoccerDay = back == 3   // one big active day mid-week
            let isShortNight = back == 5  // one rough night, for readiness contrast

            let steps: Int
            if isSoccerDay {
                steps = 15_000 + Int.random(in: 0...2_000, using: &rng)
            } else if back == 0 {
                steps = 5_000 + Int.random(in: 0...2_500, using: &rng) // today, partial day
            } else {
                steps = 4_000 + Int.random(in: 0...5_500, using: &rng)
            }
            // Roughly the vendor's scale: 8420 steps -> ~380 cal in the sample data.
            let calories = steps * 45 / 1_000

            // Same raw-dict shape the real client hands VeepooStepMapper.
            let raw: [String: Any] = ["Step": "\(steps)", "Cal": "\(calories)"]
            var record = try VeepooStepMapper.record(
                from: raw, date: Self.dateKey(for: day), deviceID: deviceID)

            let sleepMinutes: Int
            if isShortNight {
                sleepMinutes = 280 + Int.random(in: 0...40, using: &rng)
            } else {
                sleepMinutes = 390 + Int.random(in: 0...120, using: &rng)
            }
            let efficiency = isShortNight ? 0.82 : Double.random(in: 0.86...0.97, using: &rng)
            let timeInBed = Int(Double(sleepMinutes) / efficiency)
            let wakeHour = 6 + Int.random(in: 0...1, using: &rng)
            let wakeMinute = Int.random(in: 0...59, using: &rng)
            guard let wake = calendar.date(
                bySettingHour: wakeHour, minute: wakeMinute, second: 0, of: day)
            else { continue }
            let bedtime = wake.addingTimeInterval(TimeInterval(-timeInBed * 60))
            record.sleepSessions = [try SleepSession(
                start: bedtime, end: wake, estimatedSleepMinutes: sleepMinutes)]
            records.append(record)
        }
        return records
    }

    /// One tagged workout on the big active day, so session storage and the
    /// sessions UI get exercised end to end before hardware arrives.
    public func mockSessions() throws -> [ActivitySession] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let day = calendar.date(byAdding: .day, value: -3, to: today),
              let start = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: day)
        else { return [] }
        let session = try ActivitySession(
            date: Self.dateKey(for: day),
            start: start,
            end: start.addingTimeInterval(90 * 60),
            label: "Soccer",
            source: .userTagged,
            steps: 8_500)
        return [session]
    }

    static func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// Tiny deterministic RNG (linear congruential) so the mock week is identical
/// on every run. Conforms to RandomNumberGenerator for the standard
/// `Int.random(in:using:)` / `Double.random(in:using:)` helpers.
private struct LCGRandom: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 1 : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
