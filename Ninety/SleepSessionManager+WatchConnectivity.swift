import Combine
import Foundation
import UIKit
import WatchConnectivity

extension SleepSessionManager {
    // MARK: - WatchConnectivity

    func setupWatchConnectivity() {
        if WCSession.isSupported() {
            wcSession = WCSession.default
            wcSession?.delegate = self
            wcSession?.activate()
        }
    }

    func startWatchSession(targetDate: Date, alarmID: UUID? = nil, createdAt: Date? = nil) {
        resetSession()
        let monitoringStartDate = scheduledMonitoringStartDate(for: targetDate)
        activeWakeTargetDate = targetDate
        sessionStartDate = monitoringStartDate
        lastAcceptedPayloadAt = nil
        setSessionState(.scheduled)
        updateSessionRecoveryStatus("Session restarted")

        let applyQueuedState = {
            self.watchQueuedStartDate = monitoringStartDate
            self.watchReadyStartDate = nil
            self.watchStatus = "Open Ninety on Apple Watch to set Smart Alarm"
        }
        if Thread.isMainThread {
            applyQueuedState()
        } else {
            DispatchQueue.main.async(execute: applyQueuedState)
        }

        requestPersistedSessionSave()

        guard let session = wcSession else { return }

        var extra: [String: Any] = [
            "targetDate": targetDate.timeIntervalSince1970,
            "monitoringStartDate": monitoringStartDate.timeIntervalSince1970,
            "weekday": Calendar.current.component(.weekday, from: targetDate),
            "hour": Calendar.current.component(.hour, from: targetDate),
            "minute": Calendar.current.component(.minute, from: targetDate),
            "createdAt": (createdAt ?? Date()).timeIntervalSince1970
        ]
        if let alarmID {
            extra["alarmInstanceID"] = alarmID.uuidString
        }

        let command = makeWatchCommand(action: "startSession", extra: extra)

        if session.isReachable {
            session.sendMessage(command, replyHandler: nil) { error in
                self.log("Failed to start via sendMessage: \(error.localizedDescription)")
            }
            log("Direct session request sent to Watch.")
        } else {
            cancelOutstandingWatchControlTransfers(on: session)
            session.transferUserInfo(command)
            log("Watch unreachable. Request queued (Will fire when Watch wakes).".localized(for: preferredLang))
        }
    }

    func stopWatchSession() {
        activeWakeTargetDate = nil
        sessionStartDate = nil
        lastAcceptedPayloadAt = nil
        setSessionState(.completed)
        updateSessionRecoveryStatus("Session restarted")
        let clearWatchSchedulingState = {
            self.watchQueuedStartDate = nil
            self.watchReadyStartDate = nil
            self.watchStatus = "No watch session activity"
        }
        if Thread.isMainThread {
            clearWatchSchedulingState()
        } else {
            DispatchQueue.main.async(execute: clearWatchSchedulingState)
        }
        clearPersistedSessionState()
        guard let session = wcSession else { return }
        let command = makeWatchCommand(action: "stopSession")
        cancelOutstandingWatchControlTransfers(on: session)
        try? session.updateApplicationContext(command)
        if session.isReachable {
            session.sendMessage(command, replyHandler: nil) { [weak self] error in
                self?.log("Failed to stop Watch via sendMessage: \(error.localizedDescription). Queuing stop.")
                session.transferUserInfo(command)
            }
        } else {
            session.transferUserInfo(command)
        }
    }

    func pauseWatchMonitoring() {
        activeWakeTargetDate = nil
        sessionStartDate = nil
        lastAcceptedPayloadAt = nil
        setSessionState(.completed)
        updateSessionRecoveryStatus("Session restarted")
        let clearWatchSchedulingState = {
            self.watchQueuedStartDate = nil
            self.watchReadyStartDate = nil
            self.watchStatus = "No watch session activity"
        }
        if Thread.isMainThread {
            clearWatchSchedulingState()
        } else {
            DispatchQueue.main.async(execute: clearWatchSchedulingState)
        }
        clearPersistedSessionState()
        guard let session = wcSession else { return }
        let command = makeWatchCommand(action: "pauseMonitoring")
        cancelOutstandingWatchControlTransfers(on: session)
        try? session.updateApplicationContext(command)
        if session.isReachable {
            session.sendMessage(command, replyHandler: nil) { [weak self] error in
                self?.log("Failed to pause Watch via sendMessage: \(error.localizedDescription). Queuing pause.")
                session.transferUserInfo(command)
            }
        } else {
            session.transferUserInfo(command)
        }
    }

    func noteWatchSmartWakeTriggered(targetDate: Date?) {
        guard activeWakeTargetDate != nil || sessionStartDate != nil else {
            return
        }

        let detail = targetDate.map {
            "Smart wake triggered on Watch for \($0.formatted(date: .omitted, time: .shortened))"
        } ?? "Smart wake triggered on Watch"
        log(detail)
        activeWakeTargetDate = nil
        sessionStartDate = nil
        lastAcceptedPayloadAt = nil
        setSessionState(.completed)
        resetConfirmation()
        updateSessionRecoveryStatus("Smart wake triggered on Watch")
        let markWatchTriggered = {
            self.watchQueuedStartDate = nil
            self.watchReadyStartDate = nil
            self.watchStatus = "Smart wake triggered on Watch"
        }
        if Thread.isMainThread {
            markWatchTriggered()
        } else {
            DispatchQueue.main.async(execute: markWatchTriggered)
        }
        clearPersistedSessionState()
    }

    func stopWatchAlarmPlayback(alarmID: UUID? = nil, targetDate: Date? = nil, stoppedAt: Date? = nil) {
        guard let session = wcSession else { return }
        var extra: [String: Any] = [:]
        if let alarmID {
            extra["alarmInstanceID"] = alarmID.uuidString
        }
        if let targetDate {
            extra["targetDate"] = targetDate.timeIntervalSince1970
        }
        if let stoppedAt {
            extra["stoppedAt"] = stoppedAt.timeIntervalSince1970
        }
        let command = makeWatchCommand(action: "stopAlarm", extra: extra)
        cancelOutstandingWatchControlTransfers(on: session)
        try? session.updateApplicationContext(command)

        if session.isReachable {
            session.sendMessage(command, replyHandler: nil) { [weak self] error in
                self?.log("Failed to stop Watch alarm playback: \(error.localizedDescription). Queuing stop.")
                session.transferUserInfo(command)
            }
        } else {
            session.transferUserInfo(command)
        }
    }

    func syncAlarmState(targetDate: Date?, alarmID: UUID? = nil, createdAt: Date? = nil, stoppedAt: Date? = nil) {
        guard let session = wcSession else { return }
        var extra: [String: Any] = [:]
        if let targetDate {
            extra["targetDate"] = targetDate.timeIntervalSince1970
            extra["weekday"] = Calendar.current.component(.weekday, from: targetDate)
            extra["hour"] = Calendar.current.component(.hour, from: targetDate)
            extra["minute"] = Calendar.current.component(.minute, from: targetDate)
            extra["monitoringStartDate"] = scheduledMonitoringStartDate(for: targetDate).timeIntervalSince1970
        }
        if let alarmID {
            extra["alarmInstanceID"] = alarmID.uuidString
        }
        if let createdAt {
            extra["createdAt"] = createdAt.timeIntervalSince1970
        }
        if let stoppedAt {
            extra["stoppedAt"] = stoppedAt.timeIntervalSince1970
        }
        let command = makeWatchCommand(action: "syncAlarmState", extra: extra)
        if targetDate == nil {
            cancelOutstandingWatchControlTransfers(on: session)
        }
        try? session.updateApplicationContext(command)

        if session.isReachable {
            session.sendMessage(command, replyHandler: nil) { [weak self] error in
                self?.log("Failed to sync alarm state to Watch: \(error.localizedDescription). Queuing state.")
                session.transferUserInfo(command)
            }
        } else {
            session.transferUserInfo(command)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        log("WCSession Activated: \(activationState == .activated)")
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let status = session.isReachable ? "Reachable" : "Unreachable"
        log("📱 iPhone WCSession: \(status)")
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        wcSession?.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncomingPayload(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handleIncomingPayload(message, replyHandler: replyHandler)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleIncomingPayload(userInfo)
    }

}
