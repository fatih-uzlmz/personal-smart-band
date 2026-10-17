import Foundation

// MARK: - Shared math

/// Deterministic curve helpers. Every score in this file is a pure function of
/// its inputs so results are reproducible and unit-testable.
enum ScoreMath {
    /// Smoothstep between two edges; eases in and out instead of a hard ramp.
    static func smoothstep(_ x: Double, edge0: Double, edge1: Double) -> Double {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
}

/// Date validation shared by the scoring models (mirrors DailyRecord's rule).
enum ScoreDates {
    static func isValid(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return false
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value) != nil
    }
}

// MARK: - Readiness (0–100)

/// Inputs for the readiness score. Heart-rate fields are reserved and currently
/// unused; they get wired in when the band's HR sync is proven on hardware.
public struct ReadinessInputs: Sendable {
    public var sleepMinutes: Int
    public var timeInBedMinutes: Int
    public var baselineSleepMinutes: Double?
    public var restingHeartRateBpm: Double?
    public var hrvRmssdMs: Double?

    public init(sleepMinutes: Int, timeInBedMinutes: Int, baselineSleepMinutes: Double? = nil,
                restingHeartRateBpm: Double? = nil, hrvRmssdMs: Double? = nil) {
        self.sleepMinutes = sleepMinutes
        self.timeInBedMinutes = timeInBedMinutes
        self.baselineSleepMinutes = baselineSleepMinutes
        self.restingHeartRateBpm = restingHeartRateBpm
        self.hrvRmssdMs = hrvRmssdMs
    }
}

public enum ReadinessZone: String, Codable, Sendable {
    case low, moderate, high
}

public struct ReadinessScore: Codable, Equatable, Sendable {
    /// 0...100.
    public let value: Int
    public let zone: ReadinessZone
    /// Per-factor 0...1 contributions, so the app can explain the score.
    public let factors: [String: Double]

    public init(value: Int, zone: ReadinessZone, factors: [String: Double]) {
        self.value = value
        self.zone = zone
        self.factors = factors
    }
}

public enum ReadinessCalculator {
    /// How much of last night counts, and how consistently you sleep, relative
    /// to your own recent baseline. Weights: duration 50%, efficiency 30%,
    /// consistency 20% (redistributed when no baseline exists yet).
    public static func score(_ inputs: ReadinessInputs, sleepNeedMinutes: Double = 480) -> ReadinessScore {
        let duration = ScoreMath.smoothstep(Double(inputs.sleepMinutes), edge0: 240, edge1: sleepNeedMinutes)
        let efficiency: Double
        if inputs.timeInBedMinutes > 0 {
            let ratio = Double(inputs.sleepMinutes) / Double(inputs.timeInBedMinutes)
            efficiency = ScoreMath.clamp01((ratio - 0.60) / 0.30)
        } else {
            efficiency = 0
        }

        var factors: [String: Double] = ["sleepDuration": duration, "sleepEfficiency": efficiency]
        var weights: [String: Double] = ["sleepDuration": 0.625, "sleepEfficiency": 0.375]
        if let baseline = inputs.baselineSleepMinutes, baseline > 0 {
            let debt = max(0, baseline - Double(inputs.sleepMinutes))
            factors["sleepConsistency"] = ScoreMath.clamp01(1 - debt / 120)
            weights = ["sleepDuration": 0.5, "sleepEfficiency": 0.3, "sleepConsistency": 0.2]
        }

        let totalWeight = weights.values.reduce(0, +)
        let blended = weights.reduce(0) { $0 + $1.value * (factors[$1.key] ?? 0) } / totalWeight
        let value = Int((blended * 100).rounded())
        let zone: ReadinessZone = value >= 67 ? .high : (value >= 34 ? .moderate : .low)
        return ReadinessScore(value: value, zone: zone, factors: factors)
    }
}

// MARK: - Activity load (0–100)

/// Inputs for the activityLoad score. `activeMinutes` and HR-zone minutes are
/// optional until intraday and heart-rate data land; steps carry v1.
public struct ActivityLoadInputs: Sendable {
    public var steps: Int?
    public var activeMinutes: Int?
    public var vendorCaloriesKcal: Double?
    /// Reserved: minutes per HR zone, wired when the band's HR sync lands.
    public var heartRateZoneMinutes: [Int]?

    public init(steps: Int? = nil, activeMinutes: Int? = nil, vendorCaloriesKcal: Double? = nil,
                heartRateZoneMinutes: [Int]? = nil) {
        self.steps = steps
        self.activeMinutes = activeMinutes
        self.vendorCaloriesKcal = vendorCaloriesKcal
        self.heartRateZoneMinutes = heartRateZoneMinutes
    }
}

public struct ActivityLoad: Codable, Equatable, Sendable {
    /// 0...100, one decimal place. Higher points cost progressively more effort.
    public let value: Double

    public init(value: Double) {
        self.value = value
    }
}

public enum ActivityLoadCalculator {
    /// Anchored calibration, log-interpolated between anchors so each extra
    /// point demands more work than the last (diminishing-returns behavior).
    private static let stepAnchors: [(Double, Double)] = [
        (0, 0), (2_500, 5), (6_000, 9), (10_000, 12),
        (15_000, 15), (20_000, 18), (30_000, 21),
    ]
    /// Elevated-cadence minutes (from intraday buckets or tagged sessions).
    private static let minuteAnchors: [(Double, Double)] = [
        (0, 0), (15, 7), (30, 11), (60, 15), (120, 19), (240, 21),
    ]

    /// Returns nil when there is no usable input at all.
    public static func score(_ inputs: ActivityLoadInputs) -> ActivityLoad? {
        var candidates: [Double] = []
        if let steps = inputs.steps {
            candidates.append(interpolate(Double(steps), anchors: stepAnchors))
        }
        if let minutes = inputs.activeMinutes {
            candidates.append(interpolate(Double(minutes), anchors: minuteAnchors))
        }
        guard let best = candidates.max() else { return nil }
        // The internal interpolation runs on the familiar 0–21 exertion curve;
        // we surface it as a 0–100 load number so the UI speaks one scale.
        return ActivityLoad(value: (best / 21 * 100 * 10).rounded() / 10)
    }

    /// Session activityLoad is driven by sustained active minutes; step counts are
    /// recorded on the session but don't move the v1 score.
    public static func sessionScore(durationMinutes: Int) -> ActivityLoad {
        ActivityLoad(value: (interpolate(Double(durationMinutes), anchors: minuteAnchors) / 21 * 100 * 10).rounded() / 10)
    }

    private static func interpolate(_ x: Double, anchors: [(Double, Double)]) -> Double {
        guard x > 0 else { return 0 }
        guard let last = anchors.last, x < last.0 else { return anchors.last?.1 ?? 0 }
        for i in 1..<anchors.count {
            let (x0, y0) = anchors[i - 1]
            let (x1, y1) = anchors[i]
            guard x <= x1 else { continue }
            if x0 == 0 { return y0 + (x / x1) * (y1 - y0) }
            let t = log(x / x0) / log(x1 / x0)
            return y0 + t * (y1 - y0)
        }
        return anchors.last?.1 ?? 0
    }
}

// MARK: - Activity sessions (sports / workouts)

public enum BandActivityError: Error, Equatable {
    case invalidInterval
    case invalidSteps
}

public struct ActivitySession: Codable, Equatable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable {
        case userTagged
        case autoDetected
    }

    public let id: UUID
    public let date: String
    public let start: Date
    public let end: Date
    public var label: String?
    public var source: Source
    public var steps: Int?
    /// Reserved: wired when the band's heart-rate sync lands.
    public var averageHeartRateBpm: Double?
    public var peakHeartRateBpm: Double?

    public init(id: UUID = UUID(), date: String, start: Date, end: Date, label: String? = nil,
                source: Source = .userTagged, steps: Int? = nil,
                averageHeartRateBpm: Double? = nil, peakHeartRateBpm: Double? = nil) throws {
        guard ScoreDates.isValid(date) else { throw BandDataError.invalidDate }
        guard end > start else { throw BandActivityError.invalidInterval }
        guard steps.map({ $0 >= 0 }) ?? true else { throw BandActivityError.invalidSteps }
        self.id = id
        self.date = date
        self.start = start
        self.end = end
        self.label = label
        self.source = source
        self.steps = steps
        self.averageHeartRateBpm = averageHeartRateBpm
        self.peakHeartRateBpm = peakHeartRateBpm
    }

    public var durationMinutes: Int {
        Int((end.timeIntervalSince(start) / 60).rounded())
    }
}

/// One intraday step bucket (e.g. 15 minutes) as the SDK database provides.
/// The sync client will feed these in once intraday reads are validated.
public struct StepBucket: Sendable, Equatable {
    public let start: Date
    public let steps: Int

    public init(start: Date, steps: Int) throws {
        guard steps >= 0 else { throw BandActivityError.invalidSteps }
        self.start = start
        self.steps = steps
    }
}

public enum SessionDetector {
    /// Finds sustained active bouts (runs, soccer, gym) in intraday step
    /// buckets. Consecutive active buckets merge into one session; a small
    /// number of quiet buckets is tolerated inside a bout (water breaks).
    public static func detect(from buckets: [StepBucket], bucketMinutes: Int = 15,
                              activeThresholdSteps: Int = 250, maxGapBuckets: Int = 1) -> [ActivitySession] {
        let sorted = buckets.sorted { $0.start < $1.start }
        var sessions: [ActivitySession] = []
        var runStart: Int?
        var runEndExclusive = 0
        var gap = 0

        func flush() {
            guard let start = runStart, runEndExclusive > start else { return }
            let slice = sorted[start..<runEndExclusive]
            let sessionStart = slice.first!.start
            let sessionEnd = slice.last!.start.addingTimeInterval(Double(bucketMinutes * 60))
            let totalSteps = slice.reduce(0) { $0 + $1.steps }
            let day = dayKey(for: sessionStart)
            if let session = try? ActivitySession(date: day, start: sessionStart, end: sessionEnd,
                                                  source: .autoDetected, steps: totalSteps) {
                sessions.append(session)
            }
        }

        for (index, bucket) in sorted.enumerated() {
            if bucket.steps >= activeThresholdSteps {
                if runStart == nil { runStart = index; gap = 0 }
                gap = 0
                runEndExclusive = index + 1
            } else if runStart != nil {
                gap += 1
                if gap > maxGapBuckets {
                    flush()
                    runStart = nil
                }
            }
        }
        flush()
        return sessions
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Daily scores + computer

public struct DailyScores: Codable, Equatable, Sendable {
    public let date: String
    public let deviceID: String
    public var readiness: ReadinessScore?
    public var activityLoad: ActivityLoad?

    public init(date: String, deviceID: String,
                readiness: ReadinessScore? = nil, activityLoad: ActivityLoad? = nil) throws {
        guard ScoreDates.isValid(date) else { throw BandDataError.invalidDate }
        self.date = date
        self.deviceID = deviceID
        self.readiness = readiness
        self.activityLoad = activityLoad
    }
}

/// Turns synced records into scores. Pure function of the record plus trailing
/// history; the app calls it after every sync and persists the result.
public enum ScoreComputer {
    public static func scores(for record: DailyRecord, history: [DailyRecord]) -> DailyScores {
        let baseline = baselineSleepMinutes(history: history, deviceID: record.deviceID, before: record.date)

        let readiness: ReadinessScore?
        let asleep = record.sleepSessions.reduce(0) { $0 + $1.estimatedSleepMinutes }
        if asleep > 0 {
            let inBed = record.sleepSessions.reduce(0) { $0 + Int(($1.end.timeIntervalSince($1.start) / 60).rounded()) }
            readiness = ReadinessCalculator.score(ReadinessInputs(
                sleepMinutes: asleep,
                timeInBedMinutes: max(inBed, asleep),
                baselineSleepMinutes: baseline
            ))
        } else {
            readiness = nil
        }

        let activityLoad = ActivityLoadCalculator.score(ActivityLoadInputs(
            steps: record.steps,
            vendorCaloriesKcal: record.vendorCaloriesKcal
        ))

        // record.date is pre-validated by DailyRecord's initializer.
        return try! DailyScores(date: record.date, deviceID: record.deviceID,
                                readiness: readiness, activityLoad: activityLoad)
    }

    private static func baselineSleepMinutes(history: [DailyRecord], deviceID: String, before date: String) -> Double? {
        let nights = history
            .filter { $0.deviceID == deviceID && $0.date < date }
            .sorted { $0.date > $1.date }
            .prefix(7)
            .map { $0.sleepSessions.reduce(0) { $0 + $1.estimatedSleepMinutes } }
            .filter { $0 > 0 }
        guard !nights.isEmpty else { return nil }
        return Double(nights.reduce(0, +)) / Double(nights.count)
    }
}
