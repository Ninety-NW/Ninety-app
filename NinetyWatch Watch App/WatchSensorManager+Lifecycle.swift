import Foundation
import WatchKit
import HealthKit
import CoreMotion
import WatchConnectivity
import Combine
import CoreML

extension WatchSensorManager {
    func updatePipelineState(_ newState: WatchPipelineState, detail: String? = nil) {
        pipelineState = newState
        let display = detail ?? newState.label
        if Thread.isMainThread {
            sessionState = display
        } else {
            DispatchQueue.main.async {
                self.sessionState = display
            }
        }
    }

    var pendingScheduledStartDate: Date? {
        let interval = UserDefaults.standard.object(forKey: Self.pendingScheduleKey) as? TimeInterval
        return interval.map(Date.init(timeIntervalSince1970:))
    }

    var readyScheduledStartDate: Date? {
        let interval = UserDefaults.standard.object(forKey: Self.readyScheduleKey) as? TimeInterval
        return interval.map(Date.init(timeIntervalSince1970:))
    }

    func refreshNextAlarmDate() {
        let interval = UserDefaults.standard.double(forKey: Self.actualAlarmTimeKey)
        let refreshedDate: Date?

        if interval > 0 {
            let storedDate = Date(timeIntervalSince1970: interval)
            refreshedDate = storedDate > Date() ? storedDate : nil
        } else if let record = localAlarmRecord(), record.stoppedAt == nil, record.targetDate > Date() {
            refreshedDate = record.targetDate
            UserDefaults.standard.set(record.targetDate.timeIntervalSince1970, forKey: Self.actualAlarmTimeKey)
        } else {
            refreshedDate = nil
        }

        if Thread.isMainThread {
            nextAlarmDate = refreshedDate
        } else {
            DispatchQueue.main.async {
                self.nextAlarmDate = refreshedDate
            }
        }

        scheduleAlarmDeadlineTimer(for: refreshedDate)
    }

    func shouldProcessPhoneCommand(_ payload: [String: Any]) -> Bool {
        guard let sequence = intValue(from: payload["commandSequence"]) else {
            return true
        }

        let lastProcessedSequence = UserDefaults.standard.integer(
            forKey: Self.lastProcessedPhoneCommandSequenceKey
        )
        guard sequence > lastProcessedSequence else {
            return false
        }

        UserDefaults.standard.set(sequence, forKey: Self.lastProcessedPhoneCommandSequenceKey)
        return true
    }

    func intValue(from value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }

        if let number = value as? NSNumber {
            return number.intValue
        }

        if let stringValue = value as? String {
            return Int(stringValue)
        }

        return nil
    }

    func doubleValue(from value: Any?) -> Double? {
        if let doubleValue = value as? Double {
            return doubleValue
        }

        if let number = value as? NSNumber {
            return number.doubleValue
        }

        if let stringValue = value as? String {
            return Double(stringValue)
        }

        return nil
    }

    func dateValue(from value: Any?) -> Date? {
        doubleValue(from: value).map(Date.init(timeIntervalSince1970:))
    }

    func uuidValue(from value: Any?) -> UUID? {
        if let uuid = value as? UUID {
            return uuid
        }

        if let string = value as? String {
            return UUID(uuidString: string)
        }

        return nil
    }

    func incomingAlarmRecord(from payload: [String: Any], fallbackTargetDate: Date? = nil) -> WatchLocalAlarmRecord? {
        guard let targetDate = dateValue(from: payload["targetDate"]) ?? fallbackTargetDate else {
            return nil
        }

        let calendar = Calendar.current
        let alarmID = uuidValue(from: payload["alarmInstanceID"]) ?? UUID()
        let hour = intValue(from: payload["hour"]) ?? calendar.component(.hour, from: targetDate)
        let minute = intValue(from: payload["minute"]) ?? calendar.component(.minute, from: targetDate)
        let weekday = intValue(from: payload["weekday"]) ?? calendar.component(.weekday, from: targetDate)
        let createdAt = dateValue(from: payload["createdAt"]) ?? Date()
        let monitoringStart = dateValue(from: payload["monitoringStartDate"]) ?? scheduledMonitoringStartDate(for: targetDate)

        return WatchLocalAlarmRecord(
            alarmInstanceID: alarmID,
            weekday: weekday,
            hour: hour,
            minute: minute,
            targetDate: targetDate,
            monitoringStartDate: monitoringStart,
            createdAt: createdAt,
            stoppedAt: nil,
            syncState: .synced
        )
    }

    func shouldApplyIncomingRecord(_ record: WatchLocalAlarmRecord) -> Bool {
        if shouldIgnoreDueToStop(record) {
            return false
        }

        guard let local = localAlarmRecord() else {
            return true
        }

        if let stoppedAt = local.stoppedAt, stoppedAt >= record.createdAt {
            return false
        }

        if local.createdAt > record.createdAt {
            return false
        }

        if local.createdAt == record.createdAt && local.alarmInstanceID != record.alarmInstanceID {
            return false
        }

        return true
    }

    func applyIncomingAlarmRecord(_ record: WatchLocalAlarmRecord, scheduleSession: Bool) {
        guard shouldApplyIncomingRecord(record) else { return }
        saveLocalAlarmRecord(record)
        UserDefaults.standard.set(record.targetDate.timeIntervalSince1970, forKey: Self.actualAlarmTimeKey)
        refreshNextAlarmDate()
        weeklyAlarmSyncState = .synced
        weeklyAlarmSyncDetail = nil
        if scheduleSession {
            scheduleSmartAlarmSession(at: record.monitoringStartDate)
        }
    }

    func stopTombstone(from payload: [String: Any]) -> AlarmStopTombstone? {
        let stoppedAt = dateValue(from: payload["stoppedAt"]) ?? Date()
        let alarmID = uuidValue(from: payload["alarmInstanceID"])
        let targetDate = dateValue(from: payload["targetDate"])
        let createdAt = dateValue(from: payload["createdAt"])
        return AlarmStopTombstone(
            alarmInstanceID: alarmID,
            targetDate: targetDate,
            stoppedAt: stoppedAt,
            createdAt: createdAt
        )
    }

    func currentStopTombstone(stoppedAt: Date = Date()) -> AlarmStopTombstone {
        let record = localAlarmRecord()
        return AlarmStopTombstone(
            alarmInstanceID: record?.alarmInstanceID,
            targetDate: record?.targetDate ?? nextAlarmDate,
            stoppedAt: stoppedAt,
            createdAt: record?.createdAt
        )
    }

    func shouldApplyStop(_ tombstone: AlarmStopTombstone, to record: WatchLocalAlarmRecord?) -> Bool {
        guard let record else {
            return true
        }

        guard tombstone.stoppedAt >= record.createdAt else {
            return false
        }

        if let alarmID = tombstone.alarmInstanceID {
            return alarmID == record.alarmInstanceID
        }

        if let targetDate = tombstone.targetDate {
            return abs(targetDate.timeIntervalSince(record.targetDate)) < 1
        }

        return true
    }

    func applyStopTombstone(_ tombstone: AlarmStopTombstone, notifyPhone: Bool) {
        let record = localAlarmRecord()
        guard shouldApplyStop(tombstone, to: record) else { return }

        saveStopTombstone(tombstone)
        clearPendingNextAlarmCommand()
        if var record, tombstone.stoppedAt >= record.createdAt {
            record.stoppedAt = tombstone.stoppedAt
            record.syncState = .stopped
            saveLocalAlarmRecord(record)
        }

        clearScheduledAlarmAndMonitoring(
            detail: "Alarm Stopped",
            state: .idle
        )

        if notifyPhone {
            sendStopAlarmCommand(PendingStopAlarmCommand(tombstone: tombstone))
        }
    }

    func queueOrScheduleSmartAlarmSession(at date: Date) {
        guard WKExtension.shared().applicationState == .active else {
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Self.pendingScheduleKey)
            clearReadySchedule()
            updatePipelineState(.scheduled, detail: "Queued. Open Ninety to set tonight's alarm")
            sendWatchStatusUpdate("Open Ninety on Apple Watch to set Smart Alarm")
            return
        }

        scheduleSmartAlarmSession(at: date)
    }

    func clearPendingSchedule() {
        UserDefaults.standard.removeObject(forKey: Self.pendingScheduleKey)
    }

    func storeReadySchedule(_ date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Self.readyScheduleKey)
    }

    func clearReadySchedule() {
        UserDefaults.standard.removeObject(forKey: Self.readyScheduleKey)
    }

    func clearAlarmTracking(preserveLocalAlarmRecord: Bool = false) {
        alarmDeadlineTimer?.invalidate()
        alarmDeadlineTimer = nil
        UserDefaults.standard.removeObject(forKey: Self.pendingScheduleKey)
        UserDefaults.standard.removeObject(forKey: Self.readyScheduleKey)
        UserDefaults.standard.removeObject(forKey: Self.actualAlarmTimeKey)
        if !preserveLocalAlarmRecord {
            clearLocalAlarmRecord()
        }
        let shouldShowSyncedState = pendingNextAlarmCommand() == nil
        if Thread.isMainThread {
            nextAlarmDate = nil
            if shouldShowSyncedState {
                weeklyAlarmSyncState = .synced
                weeklyAlarmSyncDetail = nil
            }
        } else {
            DispatchQueue.main.async {
                self.nextAlarmDate = nil
                if shouldShowSyncedState {
                    self.weeklyAlarmSyncState = .synced
                    self.weeklyAlarmSyncDetail = nil
                }
            }
        }
    }

    func scheduleAlarmDeadlineTimer(for alarmDate: Date?) {
        let schedule = {
            self.alarmDeadlineTimer?.invalidate()
            self.alarmDeadlineTimer = nil

            guard let alarmDate else {
                return
            }

            // Fire the haptic deadline 60 seconds BEFORE the actual alarm
            let hapticDeadlineDate = alarmDate.addingTimeInterval(-60)
            let delay = hapticDeadlineDate.timeIntervalSinceNow
            guard delay > 0 else {
                _ = self.stopMonitoringIfAlarmDeadlineReached()
                return
            }

            self.alarmDeadlineTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.stopMonitoringAtAlarmDeadline()
            }
        }

        if Thread.isMainThread {
            schedule()
        } else {
            DispatchQueue.main.async(execute: schedule)
        }
    }

    @discardableResult
    func stopMonitoringIfAlarmDeadlineReached(now: Date = Date()) -> Bool {
        guard let interval = UserDefaults.standard.object(forKey: Self.actualAlarmTimeKey) as? TimeInterval else {
            return false
        }

        let alarmDate = Date(timeIntervalSince1970: interval)
        // Check against the 60-second advanced deadline
        let hapticDeadlineDate = alarmDate.addingTimeInterval(-60)
        guard now >= hapticDeadlineDate else {
            return false
        }

        stopMonitoringAtAlarmDeadline()
        return true
    }

    func stopMonitoringAtAlarmDeadline() {
        guard UserDefaults.standard.object(forKey: Self.actualAlarmTimeKey) != nil || isActivelyMonitoring else {
            return
        }

        handleScheduledAlarmReached(reason: "Alarm active (deadline)")
    }

    func sendWatchStatusUpdate(_ status: String) {
        guard let session = wcSession, session.activationState == .activated else { return }

        var message: [String: Any] = [
            "watchStatus": status,
            "statusTimestamp": Date().timeIntervalSince1970,
            "watchConnectionStatus": connectionStatus,
            "pendingPayloadCount": pendingPayloads.count,
            "replayStatus": replayStatusText,
            "pipelineState": pipelineState.rawValue
        ]
        
        if let queuedSchedule = pendingScheduledStartDate?.timeIntervalSince1970 {
            message["queuedSchedule"] = queuedSchedule
        }

        if let readySchedule = readyScheduledStartDate?.timeIntervalSince1970 {
            message["readySchedule"] = readySchedule
        }

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        } else {
            session.transferUserInfo(message)
        }
    }
    func stopActiveAlarmFromWatch() {
        let tombstone = currentStopTombstone()
        applyStopTombstone(tombstone, notifyPhone: true)
    }

    func sendStopAlarmMessage() {
        let tombstone = currentStopTombstone()
        sendStopAlarmCommand(PendingStopAlarmCommand(tombstone: tombstone))
    }
    
    func sendTriggerAlarmMessage() {
        guard let session = wcSession, session.activationState == .activated else { return }
        var message: [String: Any] = ["action": "triggerAlarm"]
        if let record = localAlarmRecord() {
            message["alarmInstanceID"] = record.alarmInstanceID.uuidString
            message["weekday"] = record.weekday
            message["hour"] = record.hour
            message["minute"] = record.minute
            message["targetDate"] = record.targetDate.timeIntervalSince1970
            message["monitoringStartDate"] = record.monitoringStartDate.timeIntervalSince1970
            message["createdAt"] = record.createdAt.timeIntervalSince1970
        } else if let nextAlarmDate {
            message["targetDate"] = nextAlarmDate.timeIntervalSince1970
        }

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        } else {
            session.transferUserInfo(message)
        }
    }
}
