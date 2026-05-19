import Foundation
import WatchKit
import HealthKit
import CoreMotion
import WatchConnectivity
import Combine
import CoreML

extension WatchSensorManager {
    func setupWatchConnectivity() {
        if WCSession.isSupported() {
            wcSession = WCSession.default
            wcSession?.delegate = self
            wcSession?.activate()
        }
    }

    func refreshConnectionStatus() {
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
        updatePipelineState(.recording, detail: "Session resumed by system")
        if extendedRuntimeSession.state == .running {
            startSensors()
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
        requestAlarmSync()
    }

    func requestAlarmSync() {
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
            }
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
    
    func scheduleSmartAlarmSession(at date: Date) {
        // Guard: watchOS rejects sessions scheduled > 36 hours in advance.
        // Queue it as a pending schedule — it will be retried when the app
        // becomes active closer to the alarm time.
        let maxScheduleLeadTime: TimeInterval = 35.5 * 3600
        if date.timeIntervalSinceNow > maxScheduleLeadTime {
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Self.pendingScheduleKey)
            let formatted = date.formatted(date: .abbreviated, time: .shortened)
            updatePipelineState(.scheduled, detail: "Queued: \(formatted)")
            sendWatchStatusUpdate(sessionState)
            return
        }

        // Guard: avoid recreating the session when already scheduled for the same date.
        if let existing = runtimeSession,
           (existing.state == .scheduled || existing.state == .running),
           let readyDate = readyScheduledStartDate,
           abs(readyDate.timeIntervalSince(date)) < 5 {
            // Same session, same start — nothing to do.
            return
        }

        #if targetEnvironment(simulator)
        self.isMocking = true
        #else
        self.isMocking = false
        #endif

        // Invalidate the existing session and park it in pendingInvalidationSessions
        // so ARC keeps it alive until the async CarouselServices RPC completes.
        // The delegate callback (didInvalidateWith) removes it from the set.
        if let existing = self.runtimeSession {
            pendingInvalidationSessions.insert(existing)
            if existing.state == .running || existing.state == .scheduled {
                suppressNextRuntimeInvalidation = true
                existing.invalidate()
            }
        }

        resetLocalAnalysis(startDate: date)
        let newSession = WKExtendedRuntimeSession()
        newSession.delegate = self
        newSession.start(at: date)
        self.runtimeSession = newSession
        storeReadySchedule(date)
        clearPendingSchedule()
        refreshNextAlarmDate()
        updatePipelineState(.scheduled, detail: "Ready for \(date.formatted(date: .omitted, time: .shortened))")
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
            self.updatePipelineState(.recording, detail: "Session Started")
            self.startSensors()
            self.sendWatchStatusUpdate(self.sessionState)
        }
    }
    
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        DispatchQueue.main.async {
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
            // Release the pending-invalidation reference now that the system has
            // confirmed the session is gone. This is the signal that it is safe
            // to let ARC free the session object.
            self.pendingInvalidationSessions.remove(extendedRuntimeSession)

            if self.suppressNextRuntimeInvalidation {
                self.suppressNextRuntimeInvalidation = false
                return
            }

            // Capture the target start date before we clear the state
            let targetStartDate = self.pendingScheduledStartDate ?? self.readyScheduledStartDate

            self.runtimeSession = nil
            self.clearReadySchedule()
            
            let nsError = error as NSError?
            let isWkError = nsError?.domain == WKExtendedRuntimeSessionErrorDomain
            let wkErrorCode = isWkError ? WKExtendedRuntimeSessionErrorCode(rawValue: nsError!.code) : nil
            
            if wkErrorCode == .mustBeActiveToStartOrSchedule {
                self.updatePipelineState(.failed, detail: "Error: Must be in foreground")
            } else if let startDate = targetStartDate {
                // H-2 Fix: Recoverable system invalidations (like system pressure or unknown errors) 
                // should be retried instead of permanently failing. We queue it for the next foreground activation.
                UserDefaults.standard.set(startDate.timeIntervalSince1970, forKey: Self.pendingScheduleKey)
                
                if wkErrorCode == .scheduledTooFarInAdvance {
                    let formatted = startDate.formatted(date: .abbreviated, time: .shortened)
                    self.updatePipelineState(.scheduled, detail: "Next alarm: \(formatted)")
                } else {
                    self.updatePipelineState(.scheduled, detail: "Retrying when opened...")
                }
            } else {
                if let wkErrorCode {
                    self.updatePipelineState(.failed, detail: "Invalidated: \(wkErrorCode.rawValue)")
                } else {
                    self.updatePipelineState(.failed, detail: "Session Invalidated")
                }
            }
            
            self.sendWatchStatusUpdate(self.sessionState)
            self.stopSensors()
        }
    }
    
}
