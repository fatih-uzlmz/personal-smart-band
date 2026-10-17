import Foundation

public enum BandDataError: Error, Equatable {
    case invalidDate
    case invalidSteps
    case invalidCalories
    case invalidSleepInterval
}

/// A vendor result is an estimate. Its calorie field must not be presented as
/// measured total energy expenditure until its meaning and accuracy are verified.
public struct DailyRecord: Codable, Equatable, Sendable {
    public let date: String
    public let deviceID: String
    public var steps: Int?
    public var vendorCaloriesKcal: Double?
    public var sleepSessions: [SleepSession]

    public init(date: String, deviceID: String, steps: Int? = nil,
                vendorCaloriesKcal: Double? = nil, sleepSessions: [SleepSession] = []) throws {
        guard Self.isValidDate(date) else { throw BandDataError.invalidDate }
        guard steps.map({ $0 >= 0 }) ?? true else { throw BandDataError.invalidSteps }
        guard vendorCaloriesKcal.map({ $0.isFinite && $0 >= 0 }) ?? true else {
            throw BandDataError.invalidCalories
        }
        self.date = date
        self.deviceID = deviceID
        self.steps = steps
        self.vendorCaloriesKcal = vendorCaloriesKcal
        self.sleepSessions = sleepSessions
    }

    private static func isValidDate(_ value: String) -> Bool {
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

public struct SleepSession: Codable, Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let estimatedSleepMinutes: Int

    public init(start: Date, end: Date, estimatedSleepMinutes: Int) throws {
        let intervalMinutes = end.timeIntervalSince(start) / 60
        guard intervalMinutes > 0, estimatedSleepMinutes >= 0,
              Double(estimatedSleepMinutes) <= intervalMinutes.rounded(.up) else {
            throw BandDataError.invalidSleepInterval
        }
        self.start = start
        self.end = end
        self.estimatedSleepMinutes = estimatedSleepMinutes
    }
}

/// Maps the documented Veepoo `Step` and `Cal` dictionary into our own model.
/// The hardware adapter can use this after a real device sync is demonstrated.
public enum VeepooStepMapper {
    public static func record(from raw: [String: Any], date: String, deviceID: String) throws -> DailyRecord {
        guard let steps = number(raw["Step"]), steps.isFinite, steps >= 0,
              steps.rounded() == steps, steps <= Double(Int.max) else {
            throw BandDataError.invalidSteps
        }
        let calories = number(raw["Cal"])
        if let calories, (!calories.isFinite || calories < 0) {
            throw BandDataError.invalidCalories
        }
        return try DailyRecord(date: date, deviceID: deviceID,
                               steps: Int(steps), vendorCaloriesKcal: calories)
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as NSNumber: return value.doubleValue
        case let value as String: return Double(value)
        default: return nil
        }
    }
}
