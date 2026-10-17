import Foundation

/// A device implementation will return its own dated records after a BLE sync.
/// The app can display and persist them without knowing the vendor protocol.
public protocol BandSyncClient {
    var displayName: String { get }
    func sync() async throws -> [DailyRecord]
}
