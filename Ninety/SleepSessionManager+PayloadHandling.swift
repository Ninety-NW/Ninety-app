import Combine
import Foundation
import UIKit
import WatchConnectivity

extension SleepSessionManager {
    // MARK: - Payload Handling

    func handleIncomingPayload(_ payloadDictionary: [String: Any], replyHandler: (([String: Any]) -> Void)? = nil) {
        // 0. Manual Alarm Sync Request
        if let action = payloadDictionary["action"] as? String, action == "requestAlarmSync" {
            DispatchQueue.main.async {
                if let activeWakeTargetDate = self.activeWakeTargetDate, activeWakeTargetDate > Date() {
                    self.syncAlarmState(
                        targetDate: activeWakeTargetDate,
                        alarmID: SmartAlarmManager.shared.currentAlarmInstanceID()
                    )
                } else if let nextSession = ScheduleViewModel(observesExternalChanges: false).nextUpcomingSession {
                    self.syncAlarmState(
                        targetDate: nextSession.wakeUpDate,
                        alarmID: SmartAlarmManager.shared.currentAlarmInstanceID()
                    )
                } else {
                    self.syncAlarmState(targetDate: nil)
                }
            }
            return
        }

        // 0.5. Cancel Alarm Request
        if let action = payloadDictionary["action"] as? String, action == "stopAlarm" {
            let tombstone = stopTombstone(from: payloadDictionary)
            recordStopTombstone(tombstone)
            DispatchQueue.main.async {
                SmartAlarmManager.shared.cancelSession(
                    alarmID: tombstone.alarmInstanceID,
                    stoppedAt: tombstone.stoppedAt
                )
            }
            return
        }

        if let action = payloadDictionary["action"] as? String, action == "watchEpochDiagnostic" {
            handleWatchEpochDiagnostic(payloadDictionary)
            return
        }

        // 0.7. Trigger Alarm Request (from Watch smart wake or fallback)
        if let action = payloadDictionary["action"] as? String, action == "triggerAlarm" {
            guard !shouldIgnoreIncomingAlarmEvent(payloadDictionary) else {
                return
            }

            if let targetDate = dateValue(from: payloadDictionary["targetDate"]),
               targetDate.addingTimeInterval(5 * 60) < Date() {
                return
            }

            let targetDate = dateValue(from: payloadDictionary["targetDate"])
            DispatchQueue.main.async {
                self.noteWatchSmartWakeTriggered(targetDate: targetDate)
            }
            return
        }

        // 1. Weekly plan edit command from the native Watch UI
        if let action = payloadDictionary["action"] as? String, action == "setNextAlarm" {
            handleSetNextAlarmFromWatch(payloadDictionary, replyHandler: replyHandler)
            return
        }

        // 2. Cross-Device Siri Intent Relay Check
        if let relayIntent = payloadDictionary["relayIntent"] as? String {
            handleRelayIntent(relayIntent, payload: payloadDictionary, replyHandler: replyHandler)
            return
        }

        // 3. Original Watch Status Check
        if handleWatchStatus(payloadDictionary) {
            return
        }

        extendBackgroundTask()

        do {
            let payload: SensorPayload
            if let payloadData = payloadDictionary["payloadData"] as? Data {
                payload = try JSONDecoder().decode(SensorPayload.self, from: payloadData)
            } else {
                let data = try JSONSerialization.data(withJSONObject: payloadDictionary, options: [])
                payload = try JSONDecoder().decode(SensorPayload.self, from: data)
            }
            let backlogPending = (payloadDictionary["pendingPayloadCount"] as? Int ?? 0) > 0

            // Deduplication and consumption must both run on processingQueue
            // to avoid data races on processed payload IDs and other shared state.
            processingQueue.async {
                guard self.shouldProcessPayload(withID: payload.id) else {
                    self.sendPayloadAcknowledgement(for: [payload.id], outcome: "Duplicate payload acknowledged")
                    return
                }

                self.lastAcceptedPayloadAt = payload.timestamp
                self.setSessionState(backlogPending ? .deliveringBacklog : .recording)
                DispatchQueue.main.async {
                    let receivedAt = Date().timeIntervalSince1970
                    let inferredWatchStatus = backlogPending ? AnalysisSessionState.deliveringBacklog.label : AnalysisSessionState.recording.label
                    let shouldLogWatchStatus = self.watchStatus != inferredWatchStatus

                    if receivedAt >= self.lastWatchStatusTimestamp {
                        self.lastWatchStatusTimestamp = receivedAt
                        self.watchStatus = inferredWatchStatus
                    }

                    self.lastPayloadReceived = "Received at \(payload.timestamp.formatted(date: .omitted, time: .standard))"
                    self.requestPersistedSessionSave()

                    if shouldLogWatchStatus {
                        self.log("Watch: \(inferredWatchStatus)")
                    }
                }

                self.recordWatchPayloadReceipt(payload)
                self.sendPayloadAcknowledgement(for: [payload.id], outcome: "Acked \(payload.id.uuidString.prefix(8))")
            }
        } catch {
            log("Decode Error: \(error.localizedDescription)")
        }
    }

    func handleWatchEpochDiagnostic(_ payloadDictionary: [String: Any]) {
        do {
            let diagnostic: WatchEpochDiagnostic
            if let diagnosticData = payloadDictionary["watchEpochData"] as? Data {
                diagnostic = try JSONDecoder().decode(WatchEpochDiagnostic.self, from: diagnosticData)
            } else {
                let data = try JSONSerialization.data(withJSONObject: payloadDictionary, options: [])
                diagnostic = try JSONDecoder().decode(WatchEpochDiagnostic.self, from: data)
            }

            processingQueue.async {
                guard self.shouldProcessWatchEpochDiagnostic(withID: diagnostic.id) else {
                    return
                }

                self.consume(watchEpochDiagnostic: diagnostic)
            }
        } catch {
            log("Watch epoch decode error: \(error.localizedDescription)")
        }
    }

    func handleSetNextAlarmFromWatch(_ payloadDictionary: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        guard !shouldIgnoreIncomingAlarmEvent(payloadDictionary) else {
            replyHandler?(["status": "stopped", "applied": false, "dialog": "Sveglia già fermata."])
            return
        }

        guard
            let hour = intValue(from: payloadDictionary["hour"]),
            let minute = intValue(from: payloadDictionary["minute"])
        else {
            replyHandler?(["error": "Comando Watch non valido. Manca l'orario."])
            return
        }

        guard (0...23).contains(hour), (0...59).contains(minute) else {
            replyHandler?(["error": "Quell'orario non è valido."])
            return
        }

        guard let targetDate = dateValue(from: payloadDictionary["targetDate"]) ?? nextWatchAlarmTargetDate(hour: hour, minute: minute) else {
            replyHandler?(["error": "Non sono riuscito a calcolare la prossima sveglia."])
            return
        }

        let targetWeekday = Calendar.current.component(.weekday, from: targetDate)
        let createdAt = doubleValue(from: payloadDictionary["createdAt"])
            .map(Date.init(timeIntervalSince1970:)) ?? Date()
        let alarmID = uuidValue(from: payloadDictionary["alarmInstanceID"])

        Task { @MainActor in
            do {
                let scheduleViewModel = ScheduleViewModel(observesExternalChanges: false)
                
                // If the user is modifying the next alarm and pushing it to a new day,
                // we should cancel the existing next alarm so it doesn't preempt the newly set one.
                if let currentNext = scheduleViewModel.nextUpcomingAlarm, currentNext.weekday != targetWeekday {
                    _ = try? await scheduleViewModel.cancelWeeklyAlarm(weekday: currentNext.weekday)
                }

                let result = try await scheduleViewModel.applyWatchWeeklyAlarm(
                    weekday: targetWeekday,
                    hour: hour,
                    minute: minute,
                    createdAt: createdAt,
                    alarmID: alarmID
                )
                let nextWakeDate = result.nextAlarm?.wakeUpDate
                self.syncAlarmState(
                    targetDate: nextWakeDate,
                    alarmID: alarmID,
                    createdAt: createdAt
                )

                var reply: [String: Any] = [
                    "status": result.isStale ? "stale" : "ok",
                    "applied": result.didApply,
                    "affectedWeekday": targetWeekday,
                    "dialog": result.isStale
                        ? self.watchStaleNextAlarmDialog(weekday: targetWeekday, nextDate: nextWakeDate)
                        : self.watchSetNextAlarmDialog(
                            weekday: targetWeekday,
                            hour: hour,
                            minute: minute,
                            nextDate: nextWakeDate
                        )
                ]

                if let nextWakeDate {
                    reply["targetDate"] = nextWakeDate.timeIntervalSince1970
                }
                if let alarmID {
                    reply["alarmInstanceID"] = alarmID.uuidString
                }

                replyHandler?(reply)
            } catch {
                replyHandler?(["error": error.localizedDescription])
            }
        }
    }

    func intValue(from value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }

        if let numberValue = value as? NSNumber {
            return numberValue.intValue
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

        if let numberValue = value as? NSNumber {
            return numberValue.doubleValue
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

        if let stringValue = value as? String {
            return UUID(uuidString: stringValue)
        }

        return nil
    }

    func stopTombstone(from payload: [String: Any]) -> AlarmStopTombstone {
        AlarmStopTombstone(
            alarmInstanceID: uuidValue(from: payload["alarmInstanceID"]),
            targetDate: dateValue(from: payload["targetDate"]),
            stoppedAt: dateValue(from: payload["stoppedAt"]) ?? Date(),
            createdAt: dateValue(from: payload["createdAt"])
        )
    }

    func storedStopTombstone() -> AlarmStopTombstone? {
        guard let data = UserDefaults.standard.data(forKey: AlarmSyncKey.stopTombstone) else {
            return nil
        }

        guard let tombstone = try? JSONDecoder().decode(AlarmStopTombstone.self, from: data) else {
            UserDefaults.standard.removeObject(forKey: AlarmSyncKey.stopTombstone)
            return nil
        }

        return tombstone
    }

    func recordStopTombstone(_ tombstone: AlarmStopTombstone) {
        if let existing = storedStopTombstone(), existing.stoppedAt > tombstone.stoppedAt {
            return
        }

        guard let data = try? JSONEncoder().encode(tombstone) else { return }
        UserDefaults.standard.set(data, forKey: AlarmSyncKey.stopTombstone)
    }

    func shouldIgnoreIncomingAlarmEvent(_ payload: [String: Any]) -> Bool {
        guard let tombstone = storedStopTombstone() else { return false }
        let createdAt = dateValue(from: payload["createdAt"]) ?? Date.distantFuture
        guard tombstone.stoppedAt >= createdAt else { return false }

        if let stoppedID = tombstone.alarmInstanceID,
           let incomingID = uuidValue(from: payload["alarmInstanceID"]) {
            return stoppedID == incomingID
        }

        if let stoppedTarget = tombstone.targetDate,
           let incomingTarget = dateValue(from: payload["targetDate"]) {
            return abs(stoppedTarget.timeIntervalSince(incomingTarget)) < 1
        }

        return false
    }

    func nextWatchAlarmTargetDate(hour: Int, minute: Int, now: Date = Date()) -> Date? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard var candidate = calendar.date(from: components) else {
            return nil
        }

        if candidate <= now {
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }

        return candidate
    }

    func watchSetNextAlarmDialog(weekday: Int, hour: Int, minute: Int, nextDate: Date?) -> String {
        let dayName = weekdayName(for: weekday)
        let time = String(format: "%02d:%02d", hour, minute)
        guard let nextDate else {
            return "Sveglia Ninety salvata per \(dayName) alle \(time)."
        }
        let nextTime = nextDate.formatted(date: .abbreviated, time: .shortened)
        return "Sveglia Ninety salvata per \(dayName) alle \(time). Prossima occorrenza: \(nextTime)."
    }

    func watchStaleNextAlarmDialog(weekday: Int, nextDate: Date?) -> String {
        let dayName = weekdayName(for: weekday)
        guard let nextDate else {
            return "L'iPhone ha una modifica più recente per \(dayName). Piano Ninety invariato."
        }
        let nextTime = nextDate.formatted(date: .abbreviated, time: .shortened)
        return "L'iPhone ha una modifica più recente per \(dayName). Prossima occorrenza: \(nextTime)."
    }

    func weekdayName(for weekday: Int) -> String {
        let preferredLang = UserDefaults.standard.string(forKey: "appLanguage") ?? "it"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: preferredLang)
        guard (1...7).contains(weekday), formatter.weekdaySymbols.indices.contains(weekday - 1) else {
            return "weekday \(weekday)"
        }
        return formatter.weekdaySymbols[weekday - 1]
    }

    func handleWatchStatus(_ payloadDictionary: [String: Any]) -> Bool {
        guard let status = payloadDictionary["watchStatus"] as? String else {
            return false
        }

        let queuedScheduleDate = (payloadDictionary["queuedSchedule"] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
        let readyScheduleDate = (payloadDictionary["readySchedule"] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
        let connectionStatus = payloadDictionary["watchConnectionStatus"] as? String
        let pendingPayloadCount = payloadDictionary["pendingPayloadCount"] as? Int
        let replayStatus = payloadDictionary["replayStatus"] as? String
        let pipelineStateRaw = payloadDictionary["pipelineState"] as? String
        let statusTimestamp = payloadDictionary["statusTimestamp"] as? TimeInterval ?? 0

        DispatchQueue.main.async {
            guard statusTimestamp >= self.lastWatchStatusTimestamp else {
                return
            }

            let shouldLogWatchStatus = self.watchStatus != status
            self.lastWatchStatusTimestamp = statusTimestamp
            self.watchStatus = status

            if let connectionStatus {
                let shouldLogConnection = self.watchConnectionStatus != connectionStatus
                self.watchConnectionStatus = connectionStatus
                if shouldLogConnection {
                    self.log("⌚️ Conn: \(connectionStatus)")
                }
            }

            self.watchQueuedStartDate = queuedScheduleDate
            self.watchReadyStartDate = readyScheduleDate

            if let pendingPayloadCount {
                self.watchPendingPayloadCount = pendingPayloadCount
            }

            if let replayStatus {
                let shouldLogReplay = self.replayStatus != replayStatus
                self.replayStatus = replayStatus
                if shouldLogReplay && replayStatus != "No backlog activity" {
                    self.log("⌚️ Replay: \(replayStatus)")
                }
            }

            if let pendingPayloadCount, pendingPayloadCount > 0 {
                self.setSessionState(.deliveringBacklog)
            } else if let pipelineStateRaw, let pipelineState = AnalysisSessionState(rawValue: pipelineStateRaw) {
                self.setSessionState(pipelineState)
            } else if self.activeWakeTargetDate != nil || self.sessionStartDate != nil {
                self.setSessionState(.recording)
            }

            self.requestPersistedSessionSave()

            if shouldLogWatchStatus {
                self.log("Watch: \(status)")
            }
        }

        return true
    }

    func sendPayloadAcknowledgement(for ids: [UUID], outcome: String) {
        guard let session = wcSession, session.activationState == .activated, !ids.isEmpty else {
            return
        }

        let message: [String: Any] = [
            "action": "ackPayloads",
            "ids": ids.map(\.uuidString)
        ]

        DispatchQueue.main.async {
            self.ackStatus = outcome
        }

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                DispatchQueue.main.async {
                    self.ackStatus = "Ack queued for \(ids.count) payload(s)"
                }
                session.transferUserInfo(message)
                self.log("Ack send failed: \(error.localizedDescription)")
            }
        } else {
            DispatchQueue.main.async {
                self.ackStatus = "Ack queued for \(ids.count) payload(s)"
            }
            session.transferUserInfo(message)
        }

        requestPersistedSessionSave()
    }

}
