#if !targetEnvironment(simulator)
import Foundation
import VeepooBleSDK

/// Errors from the Veepoo BLE sync flow.
enum VeepooSyncError: Error, LocalizedError {
    case bluetoothOff
    case noDeviceFound
    case connectFailed
    case passwordFailed
    case readFailed
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .bluetoothOff:
            return "Bluetooth is off. Turn it on and try again."
        case .noDeviceFound:
            return "No band found nearby. Make sure it is charged and close to the phone."
        case .connectFailed:
            return "Could not connect to the band."
        case .passwordFailed:
            return "Band password verification failed."
        case .readFailed:
            return "Band data read did not complete."
        case .timedOut(let step):
            return "Timed out while \(step)."
        }
    }
}

/// Real BLE adapter for the Veepoo H7 band, implementing ``BandSyncClient``.
///
/// Flow (from the Veepoo iOS API docs): scan → connect (password verification
/// happens as part of connecting) → full data read with progress → query the
/// SDK's on-device database by date + band MAC address → map into
/// ``DailyRecord`` via the existing ``VeepooStepMapper``.
///
/// The SDK does not support concurrent operations, so every step awaits the
/// previous step's callback before issuing the next command. `async`/`await`
/// gives us that serialization naturally.
final class VeepooBandSyncClient: BandSyncClient {
    var displayName: String { "Veepoo H7" }

    /// The SDK singleton (documented to always return an instance).
    private let central: VPBleCentralManage = VPBleCentralManage.sharedBleManager()!
    private let scanSeconds: TimeInterval = 8
    private let daysToSync = 7
    private let rememberedAddressKey = "com.oemband.prototype.lastBandAddress"

    init() {
        central.isLogEnable = false
        // SDK-persisted mode (recommended): the SDK keeps its own database and
        // we query it after the full read completes.
        central.peripheralManage = VPPeripheralManage.shareVPPeripheralManager()
    }

    func sync() async throws -> [DailyRecord] {
        let model = try await withTimeout(seconds: 30, step: "scanning and connecting") {
            try await self.scanAndConnect()
        }
        let address = (model.deviceAddress as String?) ?? ""
        guard !address.isEmpty else { throw VeepooSyncError.connectFailed }
        UserDefaults.standard.set(address, forKey: rememberedAddressKey)

        try await withTimeout(seconds: 180, step: "reading band data") {
            try await self.readAllData()
        }
        return queryDays(tableID: address,
                         days: daysToSync,
                         stature: UInt(model.deviceStature))
    }

    // MARK: - Scan & connect

    private func scanAndConnect() async throws -> VPPeripheralModel {
        let found = await scanForDevices(duration: scanSeconds)
        guard !found.isEmpty else { throw VeepooSyncError.noDeviceFound }
        let preferred = UserDefaults.standard.string(forKey: rememberedAddressKey)
        let target = found.first(where: { ($0.deviceAddress as String?) == preferred })
            ?? found[0]
        try await connect(to: target)
        return target
    }

    private func scanForDevices(duration: TimeInterval) async -> [VPPeripheralModel] {
        await withCheckedContinuation { continuation in
            var seen: [String: VPPeripheralModel] = [:]
            central.veepooSDKStartScanDeviceAndReceiveScanningDevice { model in
                guard let model else { return }
                let address = (model.deviceAddress as String?) ?? ""
                guard !address.isEmpty else { return }
                seen[address] = model
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                self.central.veepooSDKStopScanDevice()
                continuation.resume(returning: Array(seen.values))
            }
        }
    }

    private func connect(to model: VPPeripheralModel) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let state = ContinuationState()
            central.veepooSDKConnectDevice(model) { connectState in
                switch connectState {
                case .BleVerifyPasswordSuccess:
                    state.finish(.success(()), with: continuation)
                case .BleVerifyPasswordFailure:
                    state.finish(.failure(VeepooSyncError.passwordFailed), with: continuation)
                case .BleConnectFailed:
                    state.finish(.failure(VeepooSyncError.connectFailed), with: continuation)
                case .BlePoweredOff:
                    state.finish(.failure(VeepooSyncError.bluetoothOff), with: continuation)
                default:
                    break // BleConnecting / BleConnectSuccess: keep waiting for verification
                }
            }
        }
    }

    // MARK: - Full data read

    private func readAllData() async throws {
        guard let manage = central.peripheralManage else {
            throw VeepooSyncError.readFailed
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let state = ContinuationState()
            manage.veepooSdkStartReadDeviceAllData { readState, _, _, _ in
                switch readState {
                case .complete:
                    state.finish(.success(()), with: continuation)
                case .invalid:
                    state.finish(.failure(VeepooSyncError.readFailed), with: continuation)
                default:
                    break // Start / Reading: progress only
                }
            }
        }
    }

    // MARK: - Database queries

    private func queryDays(tableID: String, days: Int, stature: UInt) -> [DailyRecord] {
        let key = DateFormatter()
        key.locale = Locale(identifier: "en_US_POSIX")
        key.timeZone = .current
        key.dateFormat = "yyyy-MM-dd"
        var records: [DailyRecord] = []
        let calendar = Calendar.current
        for offset in 0 ..< days {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else {
                continue
            }
            let dateKey = key.string(from: date)
            let record: DailyRecord
            if let stepDict = querySteps(date: dateKey, tableID: tableID, stature: stature),
               let mapped = try? VeepooStepMapper.record(from: stepDict,
                                                         date: dateKey,
                                                         deviceID: tableID) {
                record = mapped
            } else {
                guard let empty = try? DailyRecord(date: dateKey, deviceID: tableID) else {
                    continue
                }
                record = empty
            }
            var mutable = record
            mutable.sleepSessions = querySleep(date: dateKey, tableID: tableID)
            records.append(mutable)
        }
        return records
    }

    private func querySteps(date: String, tableID: String, stature: UInt) -> [String: Any]? {
        var result: [String: Any]?
        let gate = DispatchSemaphore(value: 0)
        VPDataBaseOperation.veepooSDKGetStepData(withDate: date,
                                                andTableID: tableID,
                                                changeUserStature: stature) { dict in
            result = dict as? [String: Any]
            gate.signal()
        }
        // Local SQLite read; bail out rather than hang sync forever.
        _ = gate.wait(timeout: .now() + 10)
        return result
    }

    private func querySleep(date: String, tableID: String) -> [SleepSession] {
        guard let raw = VPDataBaseOperation.veepooSDKGetSleepData(withDate: date,
                                                                 andTableID: tableID) as? [[String: Any]] else {
            return []
        }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy/MM/dd HH:mm"
        var sessions: [SleepSession] = []
        for entry in raw {
            guard let startString = entry["SLEEP_TIME"] as? String,
                  let endString = entry["WAKE_TIME"] as? String,
                  let start = parser.date(from: startString),
                  let end = parser.date(from: endString) else {
                continue
            }
            let minutes = sleepMinutes(from: entry)
            if let session = try? SleepSession(start: start,
                                              end: end,
                                              estimatedSleepMinutes: minutes) {
                sessions.append(session)
            }
        }
        return sessions
    }

    private func sleepMinutes(from entry: [String: Any]) -> Int {
        func number(_ value: Any?) -> Double? {
            switch value {
            case let value as NSNumber: return value.doubleValue
            case let value as String: return Double(value)
            default: return nil
            }
        }
        if let hours = number(entry["SLE_HOUR"]),
           let minutes = number(entry["SLE_MINUTE"]) {
            return Int(hours * 60 + minutes)
        }
        if let deep = number(entry["DEEP_HOUR"]),
           let light = number(entry["LIGHT_HOUR"]) {
            return Int((deep + light) * 60)
        }
        return 0
    }

    // MARK: - Timeout helper

    private func withTimeout<T>(seconds: TimeInterval,
                               step: String,
                               operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw VeepooSyncError.timedOut(step)
            }
            guard let result = try await group.next() else {
                throw VeepooSyncError.timedOut(step)
            }
            group.cancelAll()
            return result
        }
    }
}

/// Guards a `CheckedContinuation` against double-resume: the SDK may invoke a
/// block more than once, and resuming twice is a runtime trap.
private final class ContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func finish(_ result: Result<Void, Error>,
               with continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        continuation.resume(with: result)
    }
}
#endif
