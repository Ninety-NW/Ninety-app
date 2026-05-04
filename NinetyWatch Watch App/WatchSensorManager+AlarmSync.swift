import Foundation
import WatchKit
import HealthKit
import CoreMotion
import WatchConnectivity
import Combine
import CoreML

extension WatchSensorManager {
    // MARK: - Mocking Data
    
    func startMockDataStream() {
        mockTimer = Timer.publish(every: payloadInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
            let mockPayload = SensorPayload(
                id: UUID(),
                timestamp: Date(),
                hrSamples: [Double.random(in: 55...65), Double.random(in: 50...60)],
                motionCount: Double.random(in: 0...30),
                accelerometerVariance: Double.random(in: 0.0...0.5),
                isMockData: true
            )
            self?.transmit(payload: mockPayload)
            self?.processPayloadForLocalSmartWake(mockPayload)
        }
    }

    func setNextAlarm(wakeTime: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: wakeTime)
        setNextAlarm(
            hour: components.hour ?? 7,
            minute: components.minute ?? 0
        )
    }

    func markNextAlarmDraftChanged() {
        guard weeklyAlarmSyncState == .saved || weeklyAlarmSyncState == .failed else {
            return
        }

        weeklyAlarmSyncState = pendingNextAlarmCommand() == nil ? .synced : .pending
        weeklyAlarmSyncDetail = nil
    }

    func setNextAlarm(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            weeklyAlarmSyncState = .failed
            weeklyAlarmSyncDetail = "Invalid alarm draft"
            return
        }

        guard let targetDate = nextLocalAlarmTargetDate(hour: hour, minute: minute) else {
            weeklyAlarmSyncState = .failed
            weeklyAlarmSyncDetail = "Unable to schedule alarm"
            return
        }

        let createdAt = Date()
        let record = WatchLocalAlarmRecord(
            alarmInstanceID: UUID(),
            weekday: Calendar.current.component(.weekday, from: targetDate),
            hour: hour,
            minute: minute,
            targetDate: targetDate,
            monitoringStartDate: scheduledMonitoringStartDate(for: targetDate),
            createdAt: createdAt,
            stoppedAt: nil,
            syncState: .watchOnly
        )

        saveLocalAlarmRecord(record)
        UserDefaults.standard.set(targetDate.timeIntervalSince1970, forKey: Self.actualAlarmTimeKey)
        refreshNextAlarmDate()
        scheduleSmartAlarmSession(at: record.monitoringStartDate)

        weeklyAlarmSyncState = .saved
        weeklyAlarmSyncDetail = "Saved on Watch"

        let command = PendingNextAlarmCommand(record: record)
        sendNextAlarmCommand(command)
    }

    // MARK: - Next Alarm Commands

    func restorePendingNextAlarmCommand() {
        guard pendingNextAlarmCommand() != nil else { return }
        weeklyAlarmSyncState = .pending
        weeklyAlarmSyncDetail = nil
    }

    func pendingNextAlarmCommand() -> PendingNextAlarmCommand? {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingNextAlarmCommandKey) else {
            return nil
        }

        guard let command = try? JSONDecoder().decode(PendingNextAlarmCommand.self, from: data) else {
            UserDefaults.standard.removeObject(forKey: Self.pendingNextAlarmCommandKey)
            return nil
        }

        return command
    }

    func persistPendingNextAlarmCommand(_ command: PendingNextAlarmCommand, state: WatchWeeklyAlarmSyncState) {
        guard let data = try? JSONEncoder().encode(command) else {
            weeklyAlarmSyncState = .failed
            weeklyAlarmSyncDetail = "Unable to store pending alarm"
            return
        }

        UserDefaults.standard.set(data, forKey: Self.pendingNextAlarmCommandKey)
        weeklyAlarmSyncState = state
        weeklyAlarmSyncDetail = nil
    }

    func clearPendingNextAlarmCommand() {
        UserDefaults.standard.removeObject(forKey: Self.pendingNextAlarmCommandKey)
    }

    func localAlarmRecord() -> WatchLocalAlarmRecord? {
        guard let data = UserDefaults.standard.data(forKey: Self.localAlarmRecordKey) else {
            return nil
        }

        guard let record = try? JSONDecoder().decode(WatchLocalAlarmRecord.self, from: data) else {
            UserDefaults.standard.removeObject(forKey: Self.localAlarmRecordKey)
            return nil
        }

        return record
    }

    func saveLocalAlarmRecord(_ record: WatchLocalAlarmRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: Self.localAlarmRecordKey)
    }

    func clearLocalAlarmRecord() {
        UserDefaults.standard.removeObject(forKey: Self.localAlarmRecordKey)
    }

    func stopTombstone() -> AlarmStopTombstone? {
        guard let data = UserDefaults.standard.data(forKey: Self.stopTombstoneKey) else {
            return nil
        }

        guard let tombstone = try? JSONDecoder().decode(AlarmStopTombstone.self, from: data) else {
            UserDefaults.standard.removeObject(forKey: Self.stopTombstoneKey)
            return nil
        }

        return tombstone
    }

    func saveStopTombstone(_ tombstone: AlarmStopTombstone) {
        if let existing = stopTombstone(), existing.stoppedAt > tombstone.stoppedAt {
            return
        }

        guard let data = try? JSONEncoder().encode(tombstone) else { return }
        UserDefaults.standard.set(data, forKey: Self.stopTombstoneKey)
    }

    func shouldIgnoreDueToStop(_ record: WatchLocalAlarmRecord) -> Bool {
        guard let tombstone = stopTombstone() else { return false }
        guard tombstone.stoppedAt >= record.createdAt else { return false }

        if let stoppedAlarmID = tombstone.alarmInstanceID, stoppedAlarmID == record.alarmInstanceID {
            return true
        }

        if let stoppedTarget = tombstone.targetDate, abs(stoppedTarget.timeIntervalSince(record.targetDate)) < 1 {
            return true
        }

        return false
    }

    func flushPendingNextAlarmCommandIfNeeded() {
        guard !isSendingNextAlarmCommand, let command = pendingNextAlarmCommand() else {
            return
        }

        sendNextAlarmCommand(command)
    }

    func sendNextAlarmCommand(_ command: PendingNextAlarmCommand) {
        guard !isSendingNextAlarmCommand else {
            persistPendingNextAlarmCommand(command, state: .pending)
            return
        }

        guard let session = wcSession, session.activationState == .activated else {
            persistPendingNextAlarmCommand(command, state: .pending)
            return
        }

        guard session.isReachable else {
            persistPendingNextAlarmCommand(command, state: .pending)
            session.transferUserInfo(command.message)
            return
        }

        isSendingNextAlarmCommand = true
        persistPendingNextAlarmCommand(command, state: .saving)
        weeklyAlarmSyncState = .saving
        weeklyAlarmSyncDetail = nil

        session.sendMessage(command.message, replyHandler: { [weak self] reply in
            DispatchQueue.main.async {
                self?.handleNextAlarmReply(reply, command: command)
            }
        }, errorHandler: { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSendingNextAlarmCommand = false
                if let pendingCommand = self.pendingNextAlarmCommand(), pendingCommand != command {
                    self.weeklyAlarmSyncState = .pending
                    self.weeklyAlarmSyncDetail = nil
                    self.flushPendingNextAlarmCommandIfNeeded()
                } else {
                    self.persistPendingNextAlarmCommand(command, state: .pending)
                    self.weeklyAlarmSyncDetail = error.localizedDescription
                }
            }
        })
    }

    func handleNextAlarmReply(_ reply: [String: Any], command: PendingNextAlarmCommand) {
        isSendingNextAlarmCommand = false

        if let pendingCommand = pendingNextAlarmCommand(), pendingCommand != command {
            weeklyAlarmSyncState = .pending
            weeklyAlarmSyncDetail = nil
            flushPendingNextAlarmCommandIfNeeded()
            return
        }

        if let error = reply["error"] as? String {
            clearPendingNextAlarmCommand()
            weeklyAlarmSyncState = .failed
            weeklyAlarmSyncDetail = error
            return
        }

        if (reply["status"] as? String) == "stopped" {
            clearPendingNextAlarmCommand()
            weeklyAlarmSyncState = .synced
            weeklyAlarmSyncDetail = reply["dialog"] as? String
            return
        }

        clearPendingNextAlarmCommand()
        weeklyAlarmSyncState = (reply["status"] as? String) == "stale" ? .synced : .saved
        weeklyAlarmSyncDetail = reply["dialog"] as? String

        if var record = localAlarmRecord(), record.alarmInstanceID == command.alarmInstanceID {
            record.syncState = .synced
            saveLocalAlarmRecord(record)
        }

        if let targetInterval = doubleValue(from: reply["targetDate"]) {
            UserDefaults.standard.set(targetInterval, forKey: Self.actualAlarmTimeKey)
            refreshNextAlarmDate()
        } else {
            requestAlarmSync()
        }
    }

    func restorePendingStopAlarmCommand() {
        guard pendingStopAlarmCommand() != nil else { return }
        flushPendingStopAlarmCommandIfNeeded()
    }

    func pendingStopAlarmCommand() -> PendingStopAlarmCommand? {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingStopAlarmCommandKey) else {
            return nil
        }

        guard let command = try? JSONDecoder().decode(PendingStopAlarmCommand.self, from: data) else {
            UserDefaults.standard.removeObject(forKey: Self.pendingStopAlarmCommandKey)
            return nil
        }

        return command
    }

    func persistPendingStopAlarmCommand(_ command: PendingStopAlarmCommand) {
        guard let data = try? JSONEncoder().encode(command) else { return }
        UserDefaults.standard.set(data, forKey: Self.pendingStopAlarmCommandKey)
    }

    func clearPendingStopAlarmCommand() {
        UserDefaults.standard.removeObject(forKey: Self.pendingStopAlarmCommandKey)
    }

    func flushPendingStopAlarmCommandIfNeeded() {
        guard let command = pendingStopAlarmCommand() else { return }
        sendStopAlarmCommand(command)
    }

    func sendStopAlarmCommand(_ command: PendingStopAlarmCommand) {
        guard let session = wcSession, session.activationState == .activated else {
            persistPendingStopAlarmCommand(command)
            return
        }

        try? session.updateApplicationContext(command.message)

        guard session.isReachable else {
            session.transferUserInfo(command.message)
            persistPendingStopAlarmCommand(command)
            return
        }

        clearPendingStopAlarmCommand()
        session.sendMessage(command.message, replyHandler: nil, errorHandler: { [weak self] _ in
            DispatchQueue.main.async {
                self?.persistPendingStopAlarmCommand(command)
                session.transferUserInfo(command.message)
            }
        })
    }

    func enableHeartRateBackgroundDelivery() {
        let hrType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        healthStore.enableBackgroundDelivery(for: hrType, frequency: .immediate) { success, error in
            if let error {
                DispatchQueue.main.async {
                    self.connectionStatus = "HK background failed: \(error.localizedDescription)"
                }
                return
            }

            if success {
                DispatchQueue.main.async {
                    if self.connectionStatus == "Disconnected" || self.connectionStatus.hasPrefix("HK background failed") {
                        self.connectionStatus = "HK background enabled"
                    }
                }
            }
        }
    }

    func standardDeviation(for values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { partialResult, value in
            partialResult + pow(value - mean, 2)
        } / Double(values.count)
        return sqrt(variance)
    }
    
}
