import Foundation
import Testing
@testable import BandCore

@Test func mapsDocumentedVeepooResult() throws {
    let record = try VeepooStepMapper.record(
        from: ["Step": "5000", "Cal": "1600.0"],
        date: "2026-09-28", deviceID: "sample-device"
    )
    #expect(record.steps == 5000)
    #expect(record.vendorCaloriesKcal == 1600)
}

@Test func rejectsBadSteps() {
    #expect(throws: BandDataError.invalidSteps) {
        try VeepooStepMapper.record(from: ["Step": -1], date: "2026-09-28", deviceID: "device")
    }
}

@Test func localStoreMergesMetricsAndStaysOnDisk() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LocalMetricStore(fileURL: directory.appendingPathComponent("metrics.json"))
    let first = try DailyRecord(date: "2026-09-28", deviceID: "device", steps: 100)
    try store.upsert(first)
    let sleep = try SleepSession(start: Date(timeIntervalSince1970: 1_000),
                                 end: Date(timeIntervalSince1970: 4_600),
                                 estimatedSleepMinutes: 50)
    let second = try DailyRecord(date: "2026-09-28", deviceID: "device", sleepSessions: [sleep])
    try store.upsert(second)
    let saved = try #require(store.load().first)
    #expect(saved.steps == 100)
    #expect(saved.sleepSessions == [sleep])
    #expect(try store.load().count == 1)
}
