import Combine
import Foundation
import UIKit
import WatchConnectivity

extension SleepSessionManager {
    // MARK: - Session State

    func setSessionState(_ newState: AnalysisSessionState, detail: String? = nil) {
        sessionState = newState
        let display = detail ?? newState.label
        if Thread.isMainThread {
            sessionStateDisplay = display
        } else {
            DispatchQueue.main.async {
                self.sessionStateDisplay = display
            }
        }
    }

    func updateSessionRecoveryStatus(_ status: String) {
        if Thread.isMainThread {
            sessionRecoveryStatus = status
        } else {
            DispatchQueue.main.async {
                self.sessionRecoveryStatus = status
            }
        }
    }

    // MARK: - Session Persistence

    var persistedSessionURL: URL? {
        guard let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let directory = supportDirectory.appendingPathComponent("Ninety", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("active_sleep_session.json")
    }

    func requestPersistedSessionSave() {
        if Thread.isMainThread {
            persistSessionStateOnMainThread()
        } else {
            DispatchQueue.main.async {
                self.persistSessionStateOnMainThread()
            }
        }
    }

    func persistSessionStateOnMainThread() {
        guard let snapshot = buildPersistedSessionStateOnMainThread() else { return }

        persistenceQueue.async {
            guard let url = self.persistedSessionURL else { return }

            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: [.atomic])
            } catch {
                DispatchQueue.main.async {
                    self.engineLog = "Session persistence failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func buildPersistedSessionStateOnMainThread() -> PersistedSessionState? {
        let publishedState = (
            lastPayloadReceived: lastPayloadReceived,
            watchStatus: watchStatus,
            watchConnectionStatus: watchConnectionStatus,
            watchQueuedStartDate: watchQueuedStartDate,
            watchReadyStartDate: watchReadyStartDate,
            watchPendingPayloadCount: watchPendingPayloadCount,
            replayStatus: replayStatus,
            ackStatus: ackStatus,
            engineLog: engineLog,
            logs: logs,
            modelStatus: modelStatus,
            rawStageDisplay: rawStageDisplay,
            officialStageDisplay: officialStageDisplay,
            latestEpochSummary: latestEpochSummary,
            latestFeatureSummary: latestFeatureSummary,
            confirmationProgress: confirmationProgress,
            sessionRecoveryStatus: sessionRecoveryStatus,
            sessionStateDisplay: sessionStateDisplay
        )

        return performOnProcessingQueueSync { () -> PersistedSessionState? in
            guard hasRestorableSession else { return nil }

            return PersistedSessionState(
                savedAt: Date(),
                lastAcceptedPayloadAt: lastAcceptedPayloadAt,
                activeWakeTargetDate: activeWakeTargetDate,
                sessionStartDate: sessionStartDate,
                sessionState: sessionState,
                processedPayloadIDs: processedPayloadIDs,
                epochHistory: epochHistory,
                rawPredictionHistory: rawPredictionHistory,
                smoothedPredictionHistory: smoothedPredictionHistory,
                confirmationBuffer: confirmationBuffer,
                isConfirming: isConfirming,
                lastPayloadReceived: publishedState.lastPayloadReceived,
                watchStatus: publishedState.watchStatus,
                watchConnectionStatus: publishedState.watchConnectionStatus,
                watchQueuedStartDate: publishedState.watchQueuedStartDate,
                watchReadyStartDate: publishedState.watchReadyStartDate,
                watchPendingPayloadCount: publishedState.watchPendingPayloadCount,
                replayStatus: publishedState.replayStatus,
                ackStatus: publishedState.ackStatus,
                engineLog: publishedState.engineLog,
                logs: publishedState.logs,
                modelStatus: publishedState.modelStatus,
                rawStageDisplay: publishedState.rawStageDisplay,
                officialStageDisplay: publishedState.officialStageDisplay,
                latestEpochSummary: publishedState.latestEpochSummary,
                latestFeatureSummary: publishedState.latestFeatureSummary,
                confirmationProgress: publishedState.confirmationProgress,
                sessionRecoveryStatus: publishedState.sessionRecoveryStatus,
                sessionStateDisplay: publishedState.sessionStateDisplay
            )
        }
    }

    func restorePersistedSessionIfValid() {
        guard let url = persistedSessionURL else {
            updateSessionRecoveryStatus("Session restarted")
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            updateSessionRecoveryStatus("Session restarted")
            return
        }

        // ── Read ──────────────────────────────────────────────────────────────
        guard let data = try? Data(contentsOf: url) else {
            // File exists but is unreadable — quarantine it and start fresh.
            quarantineCorruptSessionFile(at: url, reason: "unreadable")
            updateSessionRecoveryStatus("Session restarted (file unreadable)")
            return
        }

        // ── Decode ────────────────────────────────────────────────────────────
        // Decode failures most commonly happen after an app update that changed
        // the PersistedSessionState schema. Rather than deleting the file (and
        // losing all context for debugging), rename it to a .corrupt backup.
        guard let persisted = try? JSONDecoder().decode(PersistedSessionState.self, from: data) else {
            quarantineCorruptSessionFile(at: url, reason: "decode-failed")
            updateSessionRecoveryStatus("Session restarted (incompatible save format)")
            log("⚠️ Could not decode persisted session — saved as .corrupt for inspection.")
            return
        }

        // ── Validity ──────────────────────────────────────────────────────────
        guard shouldRestore(persisted) else {
            // Session is valid but too old — clean delete is fine here.
            clearPersistedSessionState()
            updateSessionRecoveryStatus("Session restarted (previous session expired)")
            return
        }

        // ── Restore ───────────────────────────────────────────────────────────
        applyRestoredSession(persisted)
        updateSessionRecoveryStatus("Session restored")
        log("Restored active sleep analysis from disk.")
    }

    /// Renames the session file to a `.corrupt` sibling rather than deleting it.
    /// This preserves the raw bytes for post-mortem debugging while ensuring the
    /// app starts fresh on the next launch.
    private func quarantineCorruptSessionFile(at url: URL, reason: String) {
        persistenceQueue.async {
            let backupURL = url.deletingPathExtension()
                .appendingPathExtension("\(reason).corrupt")
            // Remove any previous backup so the rename never fails with EEXIST.
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.moveItem(at: url, to: backupURL)
        }
    }


    func applyRestoredSession(_ persisted: PersistedSessionState) {
        performOnProcessingQueueSync {
            activeWakeTargetDate = persisted.activeWakeTargetDate
            sessionStartDate = persisted.sessionStartDate
            sessionState = persisted.sessionState
            lastAcceptedPayloadAt = persisted.lastAcceptedPayloadAt
            processedPayloadIDs = Array(persisted.processedPayloadIDs.suffix(maxTrackedPayloadIDs))
            processedPayloadIDSet = Set(processedPayloadIDs)
            epochHistory = persisted.epochHistory
            rawPredictionHistory = Array(persisted.rawPredictionHistory.suffix(maxStoredPredictionHistory))
            smoothedPredictionHistory = Array(persisted.smoothedPredictionHistory.suffix(maxStoredPredictionHistory))
            confirmationBuffer = persisted.confirmationBuffer
            isConfirming = persisted.isConfirming
        }

        lastPayloadReceived = persisted.lastPayloadReceived
        watchStatus = persisted.watchStatus
        watchConnectionStatus = persisted.watchConnectionStatus
        watchQueuedStartDate = persisted.watchQueuedStartDate
        watchReadyStartDate = persisted.watchReadyStartDate
        watchPendingPayloadCount = persisted.watchPendingPayloadCount
        replayStatus = persisted.replayStatus
        ackStatus = persisted.ackStatus
        engineLog = persisted.engineLog
        logs = persisted.logs
        modelStatus = persisted.modelStatus
        rawStageDisplay = persisted.rawStageDisplay
        officialStageDisplay = persisted.officialStageDisplay
        latestEpochSummary = persisted.latestEpochSummary
        latestFeatureSummary = persisted.latestFeatureSummary
        confirmationProgress = persisted.confirmationProgress
        sessionRecoveryStatus = persisted.sessionRecoveryStatus
        sessionStateDisplay = persisted.sessionStateDisplay
    }

    func shouldRestore(_ persisted: PersistedSessionState) -> Bool {
        let now = Date()
        if let targetDate = persisted.activeWakeTargetDate {
            return now <= targetDate.addingTimeInterval(persistedScheduledSessionGrace)
        }

        let lastDataDate = persisted.lastAcceptedPayloadAt ??
            persisted.epochHistory.last?.timestamp ??
            persisted.sessionStartDate ??
            persisted.savedAt

        return now.timeIntervalSince(lastDataDate) <= persistedSessionMaxAge
    }

    func clearPersistedSessionState() {
        persistenceQueue.async {
            guard let url = self.persistedSessionURL else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }

    var hasRestorableSession: Bool {
        activeWakeTargetDate != nil ||
            sessionStartDate != nil ||
            lastAcceptedPayloadAt != nil ||
            !epochHistory.isEmpty
    }

    func performOnProcessingQueueSync<T>(_ block: () -> T) -> T {
        if DispatchQueue.getSpecific(key: processingQueueKey) == processingQueueToken {
            return block()
        }

        return processingQueue.sync(execute: block)
    }

}
