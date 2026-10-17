
import Foundation
import Testing
@testable import BandCore

@Test func readinessScoresFullEfficientSleepHigh() {
    let inputs = ReadinessInputs(sleepMinutes: 480, timeInBedMinutes: 500, baselineSleepMinutes: 470)
    let score = ReadinessCalculator.score(inputs)
    #expect(score.value == 100)
    #expect(score.zone == .high)
}

@Test func readinessScoresShortFragmentedSleepLow() {
    let inputs = ReadinessInputs(sleepMinutes: 240, timeInBedMinutes: 300, baselineSleepMinutes: 450)
    let score = ReadinessCalculator.score(inputs)
    #expect(score.zone == .low)
    #expect(score.value < 34)
    #expect(score.factors["sleepDuration"] == 0)
}

@Test func readinessWorksWithoutBaseline() {
    let inputs = ReadinessInputs(sleepMinutes: 445, timeInBedMinutes: 480)
    let score = ReadinessCalculator.score(inputs)
    #expect(score.zone == .high)
    #expect(score.factors["sleepConsistency"] == nil)
}

@Test func activityLoadFollowsCalibrationAnchors() {
    #expect(ActivityLoadCalculator.score(ActivityLoadInputs(steps: 0))?.value == 0)
    #expect(abs((ActivityLoadCalculator.score(ActivityLoadInputs(steps: 10_000))?.value ?? -1) - 57.1) < 0.05)
    #expect(ActivityLoadCalculator.score(ActivityLoadInputs(steps: 30_000))?.value == 100)
    #expect(ActivityLoadCalculator.score(ActivityLoadInputs(steps: 60_000))?.value == 100)
    #expect(ActivityLoadCalculator.score(ActivityLoadInputs()) == nil)
}

@Test func activityLoadPrefersActiveMinutesOverSteps() {
    let score = ActivityLoadCalculator.score(ActivityLoadInputs(steps: 2_000, activeMinutes: 60))
    #expect(abs((score?.value ?? -1) - 71.4) < 0.05)
}

@Test func detectorFindsActiveBout() throws {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    func bucket(_ index: Int, _ steps: Int) throws -> StepBucket {
        try StepBucket(start: base.addingTimeInterval(Double(index * 900)), steps: steps)
    }
    let buckets = try [bucket(0, 20), bucket(1, 800), bucket(2, 950), bucket(3, 700), bucket(4, 30)]
    let sessions = SessionDetector.detect(from: buckets)
    #expect(sessions.count == 1)
    let session = try #require(sessions.first)
    #expect(session.steps == 2450)
    #expect(session.durationMinutes == 45)
    #expect(session.source == .autoDetected)
}

@Test func detectorSplitsSeparateBouts() throws {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    func bucket(_ index: Int, _ steps: Int) throws -> StepBucket {
        try StepBucket(start: base.addingTimeInterval(Double(index * 900)), steps: steps)
    }
    let buckets = try [bucket(0, 900), bucket(1, 900), bucket(2, 10), bucket(3, 5),
                       bucket(4, 12), bucket(5, 8), bucket(6, 850), bucket(7, 900)]
    #expect(SessionDetector.detect(from: buckets).count == 2)
}

@Test func scoreStoreRoundTripsScoresAndSessions() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LocalMetricStore(fileURL: directory.appendingPathComponent("metrics.json"))

    let scores = try DailyScores(date: "2026-09-28", deviceID: "device",
                                 readiness: ReadinessScore(value: 88, zone: .high, factors: [:]),
                                 activityLoad: ActivityLoad(value: 54.8))
    try store.saveScore(scores)
    #expect(try store.loadScores() == [scores])

    let session = try ActivitySession(date: "2026-09-28",
                                      start: Date(timeIntervalSince1970: 2_000),
                                      end: Date(timeIntervalSince1970: 5_600),
                                      label: "Soccer", source: .userTagged, steps: 3200)
    try store.saveSession(session)
    #expect(try store.loadSessions() == [session])
}

@Test func scoreComputerBuildsDailyScores() throws {
    func record(_ date: String, sleep: Int) throws -> DailyRecord {
        var record = try DailyRecord(date: date, deviceID: "device", steps: 10_000)
        let start = Date(timeIntervalSince1970: 1_000)
        record.sleepSessions = [try SleepSession(start: start,
                                                 end: start.addingTimeInterval(Double(sleep + 20) * 60),
                                                 estimatedSleepMinutes: sleep)]
        return record
    }
    let history = try [record("2026-09-25", sleep: 450), record("2026-09-26", sleep: 450)]
    let today = try record("2026-09-28", sleep: 480)
    let scores = ScoreComputer.scores(for: today, history: history)
    #expect(scores.date == "2026-09-28")
    #expect(scores.readiness?.zone == .high)
    #expect(abs((scores.activityLoad?.value ?? -1) - 57.1) < 0.05)
}

@Test func scoreComputerHandlesMissingData() throws {
    let record = try DailyRecord(date: "2026-09-28", deviceID: "device")
    let scores = ScoreComputer.scores(for: record, history: [])
    #expect(scores.readiness == nil)
    #expect(scores.activityLoad == nil)
}


// MARK: - Mock band week (pre-hardware pipeline)

@Test func mockWeekIsDeterministic() async throws {
    let first = try await MockBandSyncClient().sync()
    let second = try await MockBandSyncClient().sync()
    #expect(first.count == 7)
    #expect(first == second)
    #expect(first.allSatisfy { $0.deviceID == "mock-h7" })
    // Chronological, one record per day.
    #expect(first.map(\.date) == first.map(\.date).sorted())
    #expect(Set(first.map(\.date)).count == 7)
}

@Test func mockWeekHasPlausibleVariety() async throws {
    let records = try await MockBandSyncClient().sync()
    let steps = records.compactMap(\.steps)
    #expect(steps.max() ?? 0 >= 14_000)   // the soccer day
    #expect(steps.min() ?? 0 <= 9_500)     // ordinary days
    // Every record carries the sleep session for the night that ended that morning.
    #expect(records.allSatisfy { $0.sleepSessions.count == 1 })
    let sleep = records.flatMap(\.sleepSessions).map(\.estimatedSleepMinutes)
    #expect(sleep.min() ?? 0 < 340)        // the short night
    #expect(sleep.max() ?? 0 >= 450)       // a full night
}

@Test func mockWeekFlowsThroughScoring() async throws {
    let records = try await MockBandSyncClient().sync()
    let scores = records.map { ScoreComputer.scores(for: $0, history: records) }
    #expect(scores.allSatisfy { $0.readiness != nil && $0.activityLoad != nil })
    // The short night should read clearly worse than the best night.
    let readiness = scores.compactMap { $0.readiness?.value }
    #expect((readiness.max() ?? 0) - (readiness.min() ?? 100) > 10)
    // The soccer day should clearly top the week's load.
    let loads = scores.compactMap { $0.activityLoad?.value }
    let maxLoad = loads.max() ?? 0
    #expect(maxLoad > 70)
    let maxStepsDay = records.max { ($0.steps ?? 0) < ($1.steps ?? 0) }?.date
    #expect(scores.first { $0.activityLoad?.value == maxLoad }?.date == maxStepsDay)
}

@Test func mockSessionsTagSoccerDay() throws {
    let sessions = try MockBandSyncClient().mockSessions()
    #expect(sessions.count == 1)
    let session = try #require(sessions.first)
    #expect(session.label == "Soccer")
    #expect(session.source == .userTagged)
    #expect(session.durationMinutes == 90)
}
