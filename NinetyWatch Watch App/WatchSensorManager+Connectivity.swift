import Foundation
import WatchKit
import HealthKit
import CoreMotion
import WatchConnectivity
import Combine
import CoreML

extension WatchSensorManager {
    func setupWatchConnectivity() {
        guard WatchPhoneSyncConfiguration.isPhoneSyncEnabled else {
            wcSession = nil
            connectionStatus = "Phone sync disabled"
            return
        }

        if WCSession.isSupported() {
            wcSession = WCSession.default
            wcSession?.delegate = self
            wcSession?.activate()
        }
    }

    func refreshConnectionStatus() {
        guard WatchPhoneSyncConfiguration.isPhoneSyncEnabled else {
            connectionStatus = "Phone sync disabled"
            return
        }

        guard let session = wcSession else {
            connectionStatus = "Disconnected"
            sendWatchStatusUpdate(sessionState)
            return
        }

        guard session.activationState == .activated else {
            connectionStatus = "Session not activated"
            sendWatchStatusUpdate(sessionState)
            return
        }

        if session.isReachable {
            connectionStatus = pendingPayloads.isEmpty ? "Phone reachable" : "Phone reachable, pending \(pendingPayloads.count)"
        } else {
            connectionStatus = pendingPayloads.isEmpty ? "Phone unavailable, queued delivery" : "Phone unavailable, pending \(pendingPayloads.count)"
        }
        sendWatchStatusUpdate(sessionState)
        flushPendingPayloadsIfNeeded(force: session.isReachable)
        flushPendingNextAlarmCommandIfNeeded()
        flushPendingStopAlarmCommandIfNeeded()
    }

    func retryPendingPayloadDelivery() {
        guard WatchPhoneSyncConfiguration.isPhoneSyncEnabled else {
            refreshConnectionStatus()
            return
        }

        refreshConnectionStatus()
        flushPendingPayloadsIfNeeded(force: true)
        flushPendingNextAlarmCommandIfNeeded()
        flushPendingStopAlarmCommandIfNeeded()
    }

    func resumeScheduledSession(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        runtimeSession = extendedRuntimeSession
        runtimeSession?.delegate = self
        clearPendingSchedule()
        clearReadySchedule()
        runtimeStatus = "Resumed by system: \(runtimeStateDescription(extendedRuntimeSession.state))"
        updatePipelineState(.recording, detail: "Session resumed by system")
        startSensorsIfRuntimeIsRunning(reason: "resume handle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.startSensorsIfRuntimeIsRunning(reason: "resume retry")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.startSensorsIfRuntimeIsRunning(reason: "resume late retry")
        }
        sendWatchStatusUpdate(sessionState)
    }

    func refreshStoredAlarmStateIfNeeded() {
        if let interval = UserDefaults.standard.object(forKey: Self.actualAlarmTimeKey) as? TimeInterval {
            let storedDate = Date(timeIntervalSince1970: interval)
            if storedDate <= Date() {
                clearAlarmTracking()
                return
            }
        }

        if let interval = UserDefaults.standard.object(forKey: Self.pendingScheduleKey) as? TimeInterval {
            let pendingDate = Date(timeIntervalSince1970: interval)
            if pendingDate <= Date() {
                clearPendingSchedule()
            }
        }

        refreshNextAlarmDate()
        recoverMonitoringIfNeeded(reason: "stored alarm recovery")
        if WatchPhoneSyncConfiguration.isPhoneSyncEnabled {
            requestAlarmSync()
        }
    }

    func requestAlarmSync() {
        guard WatchPhoneSyncConfiguration.isPhoneSyncEnabled else { return }
        guard let session = wcSession, session.activationState == .activated else { return }
        let message = ["action": "requestAlarmSync"]
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        } else {
            session.transferUserInfo(message)
        }
    }

    func requestHealthPermissions(completion: @escaping (Bool) -> Void) {
        let hrType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        healthStore.requestAuthorization(toShare: nil, read: [hrType]) { success, _ in
            if success {
                self.enableHeartRateBackgroundDelivery()
            } else {
                DispatchQueue.main.async {
                    self.sensorStatus = "Health permission denied"
                }
            }
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
    
    func scheduleSmartAlarmSession(at date: Date) {
        let startDate = date <= Date() ? Date().addingTimeInterval(2) : date
        #if targetEnvironment(simulator)
        self.isMocking = true
        #else
        self.isMocking = false
        #endif

        if let existing = self.runtimeSession {
            if existing.state == .running || existing.state == .scheduled {
                suppressNextRuntimeInvalidation = true
                existing.invalidate()
            }
        }

        refreshAutoLaunchStatus()
        resetLocalAnalysis(startDate: startDate)
        self.runtimeSession = WKExtendedRuntimeSession()
        self.runtimeSession?.delegate = self
        self.runtimeSession?.start(at: startDate)
        runtimeStatus = "Scheduled: \(runtimeStateDescription(self.runtimeSession?.state))"
        storeReadySchedule(startDate)
        clearPendingSchedule()
        refreshNextAlarmDate()
        updatePipelineState(.scheduled, detail: "Ready for \(startDate.formatted(date: .omitted, time: .shortened))")
        sendWatchStatusUpdate(sessionState)
    }

    func setPendingScheduleIfPossible() {
        guard let date = pendingScheduledStartDate else { return }

        guard WKExtension.shared().applicationState == .active else {
            DispatchQueue.main.async {
                self.updatePipelineState(.scheduled, detail: "Open Ninety to set tonight's alarm")
            }
            sendWatchStatusUpdate("Open Ninety on Apple Watch to set Smart Alarm")
            return
        }

        scheduleSmartAlarmSession(at: date)
    }

    func refreshAutoLaunchStatus() {
        WKExtendedRuntimeSession.requestAutoLaunchAuthorizationStatus { status, error in
            DispatchQueue.main.async {
                if let error {
                    self.autoLaunchStatus = "Error: \(error.localizedDescription)"
                    return
                }

                switch status {
                case .active:
                    self.autoLaunchStatus = "Active"
                case .inactive:
                    self.autoLaunchStatus = "Inactive"
                case .unknown:
                    self.autoLaunchStatus = "Unknown"
                @unknown default:
                    self.autoLaunchStatus = "Unknown"
                }
            }
        }
    }

    func runtimeStateDescription(_ state: WKExtendedRuntimeSessionState?) -> String {
        guard let state else { return "nil" }
        switch state {
        case .notStarted:
            return "not started"
        case .scheduled:
            return "scheduled"
        case .running:
            return "running"
        case .invalid:
            return "invalid"
        @unknown default:
            return "unknown"
        }
    }

    func startSensorsIfRuntimeIsRunning(reason: String) {
        guard runtimeSession?.state == .running else {
            runtimeStatus = "Waiting runtime: \(runtimeStateDescription(runtimeSession?.state))"
            return
        }

        runtimeStatus = "Running"
        updatePipelineState(.recording, detail: "Recording (\(reason))")
        startSensors()
    }

    func recoverMonitoringIfNeeded(reason: String) {
        refreshAutoLaunchStatus()
        guard !sensorsRunning else { return }
        guard let targetDate = currentAlarmTargetDate(), Date() < targetDate else { return }

        let monitoringStart = localAlarmRecord()?.monitoringStartDate ??
            targetDate.addingTimeInterval(-monitoringLeadTime)
        guard Date() >= monitoringStart else { return }

        if runtimeSession?.state == .running {
            startSensorsIfRuntimeIsRunning(reason: reason)
            return
        }

        guard WKExtension.shared().applicationState == .active else {
            updatePipelineState(.scheduled, detail: "Monitoring due, waiting auto-launch")
            runtimeStatus = "Due but app inactive"
            return
        }

        let repairDate = Date().addingTimeInterval(2)
        runtimeStatus = "Repair scheduling now"
        updatePipelineState(.scheduled, detail: "Repairing monitor start")
        scheduleSmartAlarmSession(at: repairDate)
    }
    
    func stopSession() {
        clearScheduledAlarmAndMonitoring(
            detail: "Manually Stopped",
            state: .completed
        )
    }

    func pauseMonitoring() {
        clearScheduledAlarmAndMonitoring(
            detail: "Monitoring Paused After Alarm",
            state: .completed
        )
    }

    // MARK: - WKExtendedRuntimeSessionDelegate
    
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        DispatchQueue.main.async {
            self.runtimeSession = extendedRuntimeSession
            self.clearReadySchedule()
            self.runtimeStatus = "Started"
            self.updatePipelineState(.recording, detail: "Session Started")
            self.startSensors()
            self.sendWatchStatusUpdate(self.sessionState)
        }
    }
    
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        DispatchQueue.main.async {
            self.runtimeStatus = "Will expire"
            self.updatePipelineState(.recording, detail: "Session Expiring Soon")
            self.sendWatchStatusUpdate(self.sessionState)

            guard
                let nextAlarmDate = self.nextAlarmDate,
                nextAlarmDate.timeIntervalSinceNow <= self.runtimeExpiryAlarmTolerance
            else {
                return
            }

            self.handleScheduledAlarmReached(reason: "Alarm active (runtime deadline)")
        }
    }
    
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        DispatchQueue.main.async {
            if self.suppressNextRuntimeInvalidation {
                self.suppressNextRuntimeInvalidation = false
                return
            }

            self.runtimeSession = nil
            self.clearReadySchedule()
            self.runtimeStatus = "Invalidated"
            if
                let nsError = error as NSError?,
                nsError.domain == WKExtendedRuntimeSessionErrorDomain,
                let wkErrorCode = WKExtendedRuntimeSessionErrorCode(rawValue: nsError.code)
            {
                switch wkErrorCode {
                case .scheduledTooFarInAdvance:
                    // future day (>36h away). Re-queue it so the Watch sets it automatically
                    // when opened closer to bedtime.
                    if let startDate = self.pendingScheduledStartDate ?? self.readyScheduledStartDate {
                        UserDefaults.standard.set(startDate.timeIntervalSince1970, forKey: Self.pendingScheduleKey)
                        let formatted = startDate.formatted(date: .abbreviated, time: .shortened)
                        self.updatePipelineState(.scheduled, detail: "Next alarm: \(formatted)")
                    } else {
                        self.updatePipelineState(.idle, detail: "Open Ninety to set alarm")
                    }
                case .mustBeActiveToStartOrSchedule:
                    self.updatePipelineState(.failed, detail: "Error: Must be in foreground")
                default:
                    self.updatePipelineState(.failed, detail: "Invalidated: \(wkErrorCode.rawValue)")
                }
            } else {
                self.updatePipelineState(.failed, detail: "Session Invalidated")
            }
            self.sendWatchStatusUpdate(self.sessionState)
            self.stopSensors()
        }
    }
    
}
