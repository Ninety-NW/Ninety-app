import Foundation
import WatchKit
import HealthKit
import CoreMotion
import WatchConnectivity
import Combine
import CoreML

extension WatchSensorManager {
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.refreshConnectionStatus()
            if activationState == .activated {
                self.requestAlarmSync()
            }
            self.flushPendingPayloadsIfNeeded(force: true)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.refreshConnectionStatus()
            if session.isReachable {
                self.requestAlarmSync()
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        processIncomingCommand(message)
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        processIncomingCommand(userInfo)
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        processIncomingCommand(applicationContext)
    }
    
    func processIncomingCommand(_ payload: [String: Any]) {
        if let action = payload["action"] as? String {
            if action == "ackPayloads" {
                let idStrings = payload["ids"] as? [String] ?? []
                DispatchQueue.main.async {
                    self.acknowledgePayloads(withIDs: idStrings.compactMap(UUID.init(uuidString:)))
                }
            } else if action == "startSession" {
                guard shouldProcessPhoneCommand(payload) else { return }
                guard let targetInterval = doubleValue(from: payload["targetDate"]) else { return }
                let targetDate = Date(timeIntervalSince1970: targetInterval)
                guard let record = incomingAlarmRecord(from: payload, fallbackTargetDate: targetDate) else { return }
                DispatchQueue.main.async {
                    guard self.shouldApplyIncomingRecord(record) else { return }
                    self.prepareForNewSession()
                    self.applyIncomingAlarmRecord(record, scheduleSession: false)
                    self.queueOrScheduleSmartAlarmSession(at: record.monitoringStartDate)
                }
            } else if action == "stopSession" {
                guard shouldProcessPhoneCommand(payload) else { return }
                DispatchQueue.main.async {
                    guard !self.hasUnsyncedLocalAlarm else { return }
                    self.stopSession()
                }
            } else if action == "pauseMonitoring" {
                guard shouldProcessPhoneCommand(payload) else { return }
                DispatchQueue.main.async {
                    guard !self.hasUnsyncedLocalAlarm else { return }
                    self.pauseMonitoring()
                }
            } else if action == "stopAlarm" {
                guard shouldProcessPhoneCommand(payload) else { return }
                let tombstone = stopTombstone(from: payload) ?? currentStopTombstone()
                DispatchQueue.main.async {
                    self.applyStopTombstone(tombstone, notifyPhone: false)
                }
            } else if action == "syncAlarmState" {
                guard shouldProcessPhoneCommand(payload) else { return }
                if let stoppedAt = payload["stoppedAt"] {
                    let tombstone = stopTombstone(from: payload) ?? AlarmStopTombstone(
                        alarmInstanceID: uuidValue(from: payload["alarmInstanceID"]),
                        targetDate: dateValue(from: payload["targetDate"]),
                        stoppedAt: dateValue(from: stoppedAt) ?? Date(),
                        createdAt: dateValue(from: payload["createdAt"])
                    )
                    DispatchQueue.main.async {
                        self.applyStopTombstone(tombstone, notifyPhone: false)
                    }
                    return
                }

                if let targetInterval = doubleValue(from: payload["targetDate"]) {
                    let targetDate = Date(timeIntervalSince1970: targetInterval)
                    let record = incomingAlarmRecord(from: payload, fallbackTargetDate: targetDate)
                    print("WATCH: Received syncAlarmState for \(targetDate)")
                    DispatchQueue.main.async {
                        if let record {
                            self.applyIncomingAlarmRecord(record, scheduleSession: false)
                        } else {
                            UserDefaults.standard.set(targetInterval, forKey: Self.actualAlarmTimeKey)
                            self.refreshNextAlarmDate()
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        if let record = self.localAlarmRecord(), record.syncState != .synced {
                            return
                        }
                        self.clearScheduledAlarmAndMonitoring(
                            detail: "Alarm Removed",
                            state: .idle
                        )
                    }
                    print("WATCH: Received syncAlarmState (clear)")
                }
            }
        }
    }

}
