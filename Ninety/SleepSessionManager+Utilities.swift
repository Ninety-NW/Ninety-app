import Combine
import Foundation
import UIKit
import WatchConnectivity

extension SleepSessionManager {
    // MARK: - Session Reset

    func resetSession() {
        performOnProcessingQueueSync {
            self.epochHistory.removeAll()
            self.rawPredictionHistory.removeAll()
            self.smoothedPredictionHistory.removeAll()
            self.processedPayloadIDSet.removeAll()
            self.processedPayloadIDs.removeAll()
            self.processedWatchEpochDiagnosticIDSet.removeAll()
            self.processedWatchEpochDiagnosticIDs.removeAll()
            self.activeWakeTargetDate = nil
            self.isConfirming = false
            self.confirmationBuffer.removeAll()
            self.sessionStartDate = nil
            self.lastAcceptedPayloadAt = nil
            self.lastWatchStatusTimestamp = 0
            self.sessionState = .idle
            self.clearPersistedSessionState()

            DispatchQueue.main.async {
                self.rawStageDisplay = "Warming up (5 epochs)".localized(for: self.preferredLang)
                self.officialStageDisplay = "Warming up (5 epochs)".localized(for: self.preferredLang)
                self.latestEpochSummary = "No 30-second epoch yet".localized(for: self.preferredLang)
                self.latestFeatureSummary = "No features computed yet".localized(for: self.preferredLang)
                self.confirmationProgress = "Idle"
                self.replayStatus = "No backlog activity"
                self.ackStatus = "No acknowledgements yet"
                self.watchQueuedStartDate = nil
                self.watchReadyStartDate = nil
                self.watchPendingPayloadCount = 0
                self.sessionStateDisplay = AnalysisSessionState.idle.label
            }
        }
    }

    // MARK: - Utilities

    func shouldProcessPayload(withID id: UUID) -> Bool {
        guard !processedPayloadIDSet.contains(id) else {
            return false
        }

        processedPayloadIDs.append(id)
        processedPayloadIDSet.insert(id)
        if processedPayloadIDs.count > maxTrackedPayloadIDs {
            let overflowCount = processedPayloadIDs.count - maxTrackedPayloadIDs
            let removedIDs = processedPayloadIDs.prefix(overflowCount)
            processedPayloadIDs.removeFirst(overflowCount)
            removedIDs.forEach { processedPayloadIDSet.remove($0) }
        }
        return true
    }

    func shouldProcessWatchEpochDiagnostic(withID id: UUID) -> Bool {
        guard !processedWatchEpochDiagnosticIDSet.contains(id) else {
            return false
        }

        processedWatchEpochDiagnosticIDs.append(id)
        processedWatchEpochDiagnosticIDSet.insert(id)
        if processedWatchEpochDiagnosticIDs.count > maxTrackedPayloadIDs {
            let overflowCount = processedWatchEpochDiagnosticIDs.count - maxTrackedPayloadIDs
            let removedIDs = processedWatchEpochDiagnosticIDs.prefix(overflowCount)
            processedWatchEpochDiagnosticIDs.removeFirst(overflowCount)
            removedIDs.forEach { processedWatchEpochDiagnosticIDSet.remove($0) }
        }
        return true
    }

    func scheduledMonitoringStartDate(for wakeTargetDate: Date) -> Date {
        let requestedStart = wakeTargetDate.addingTimeInterval(-SmartAlarmManager.monitoringLeadTime)
        if requestedStart <= Date() {
            return Date().addingTimeInterval(2)
        }
        return requestedStart
    }

    func makeWatchCommand(action: String, extra: [String: Any] = [:]) -> [String: Any] {
        var command = extra
        command["action"] = action
        command["commandSequence"] = nextWatchCommandSequence()
        return command
    }

    func nextWatchCommandSequence() -> Int {
        let nextValue = UserDefaults.standard.integer(forKey: WatchCommandKey.sequence) + 1
        UserDefaults.standard.set(nextValue, forKey: WatchCommandKey.sequence)
        return nextValue
    }

    func cancelOutstandingWatchControlTransfers(on session: WCSession) {
        let controlActions: Set<String> = ["startSession", "stopSession", "pauseMonitoring", "syncAlarmState", "stopAlarm"]
        for transfer in session.outstandingUserInfoTransfers {
            guard
                let action = transfer.userInfo["action"] as? String,
                controlActions.contains(action)
            else {
                continue
            }
            transfer.cancel()
        }
    }

    func log(_ message: String) {
        DispatchQueue.main.async {
            self.logs.insert("[\(Date().formatted(date: .omitted, time: .standard))] \(message)", at: 0)
            if self.logs.count > 5000 {
                self.logs.removeLast()
            }
            self.engineLog = message
            self.requestPersistedSessionSave()
        }
    }

    func clearLogs() {
        DispatchQueue.main.async {
            self.logs.removeAll()
            self.epochHistory.removeAll()
            self.rawPredictionHistory.removeAll()
            self.smoothedPredictionHistory.removeAll()
            self.confirmationBuffer.removeAll()
            self.processedWatchEpochDiagnosticIDSet.removeAll()
            self.processedWatchEpochDiagnosticIDs.removeAll()
            self.requestPersistedSessionSave()
        }
    }

    func extendBackgroundTask() {
        let application = UIApplication.shared
        let previousTask = currentBackgroundTask

        currentBackgroundTask = application.beginBackgroundTask(withName: "SleepProcessing") {
            application.endBackgroundTask(self.currentBackgroundTask)
            self.currentBackgroundTask = .invalid
            self.log("Background task expired")
        }

        if previousTask != .invalid {
            application.endBackgroundTask(previousTask)
        }
    }

    func updateModelStatus(_ status: String) {
        DispatchQueue.main.async {
            self.modelStatus = status
        }
        log(status)
    }

    // MARK: - Math Helpers

    func mean(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    func stdDev(of values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let avg = mean(of: values)
        let variance = values.reduce(0) { partialResult, value in
            partialResult + pow(value - avg, 2)
        } / Double(values.count)
        return sqrt(variance)
    }

    func log1p(_ x: Double) -> Double {
        return Foundation.log1p(max(x, 0))
    }
}
