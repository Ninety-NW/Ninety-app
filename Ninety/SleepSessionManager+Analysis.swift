import Foundation

extension SleepSessionManager {
    // MARK: - Cross-Device Intent Handlers

    func handleRelayIntent(_ action: String, payload: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        Task { @MainActor in
            do {
                let dialog = try await NinetyAlarmIntentService.dialogForRelay(
                    action: action,
                    payload: payload
                )
                self.log("Relayed Siri intent: \(action)")
                replyHandler?(["dialog": dialog])
            } catch {
                let message = error.localizedDescription
                self.log("Relayed Siri intent failed: \(action) - \(message)")
                replyHandler?(["error": message])
            }
        }
    }

    // MARK: - Watch Diagnostics

    func recordWatchPayloadReceipt(_ payload: SensorPayload) {
        lastAcceptedPayloadAt = payload.timestamp
        requestPersistedSessionSave()
    }

    func consume(watchEpochDiagnostic diagnostic: WatchEpochDiagnostic) {
        defer {
            requestPersistedSessionSave()
        }

        let stage = diagnostic.smoothedStage.flatMap { SleepStage(rawValue: $0) }
        let rawStage = diagnostic.rawStage.flatMap { SleepStage(rawValue: $0) }
        let stageText = stage?.title ?? diagnostic.stageTitle
        let rawStageText = rawStage?.title ?? diagnostic.stageTitle

        let epoch = EpochAggregate(
            timestamp: diagnostic.timestamp,
            processedAt: diagnostic.processedAt,
            heartRateMean: diagnostic.heartRateMean,
            heartRateStd: diagnostic.heartRateStd,
            heartRateRange: diagnostic.heartRateRange,
            motionMagMean: diagnostic.motionMagMean,
            motionMagMax: diagnostic.motionMagMax,
            motionJerk: diagnostic.motionJerk,
            modelStage: stageText,
            isWatchTestInjected: diagnostic.isTestInjected
        )

        if let lastEpoch = epochHistory.last, diagnostic.timestamp.timeIntervalSince(lastEpoch.timestamp) > 300 {
            epochHistory.removeAll()
            rawPredictionHistory.removeAll()
            smoothedPredictionHistory.removeAll()
            log("Large Watch epoch gap. Resetting displayed history while Watch rebuilds its ML buffer.")
        }

        epochHistory.append(epoch)
        trimEpochHistoryIfNeeded()

        if let rawStage {
            rawPredictionHistory.append(rawStage)
            if rawPredictionHistory.count > maxStoredPredictionHistory {
                rawPredictionHistory.removeFirst(rawPredictionHistory.count - maxStoredPredictionHistory)
            }
        }

        if let stage {
            smoothedPredictionHistory.append(stage)
            if smoothedPredictionHistory.count > maxStoredPredictionHistory {
                smoothedPredictionHistory.removeFirst(smoothedPredictionHistory.count - maxStoredPredictionHistory)
            }
        }

        updateEpochSummary(for: epoch)

        let featureSummary = String(
            format: "Watch epoch | HR %.1f bpm | Motion %.1f | Jerk %.2f",
            epoch.heartRateMean,
            epoch.motionMagMean,
            epoch.motionJerk
        )

        DispatchQueue.main.async {
            self.rawStageDisplay = rawStageText
            self.officialStageDisplay = stageText
            self.latestFeatureSummary = featureSummary
            self.modelStatus = "Watch-side model active"
        }

        log("Watch epoch displayed. Stage: \(stageText)")
    }

    func trimEpochHistoryIfNeeded() {
        if epochHistory.count > maxStoredPredictionHistory {
            epochHistory.removeFirst(epochHistory.count - maxStoredPredictionHistory)
        }
    }

    func updateEpochSummary(for epoch: EpochAggregate) {
        let summary = String(
            format: "%@ | HR %.1f bpm | Motion %.0f",
            epoch.timestamp.formatted(date: .omitted, time: .standard),
            epoch.heartRateMean,
            epoch.motionMagMean
        )

        DispatchQueue.main.async {
            self.latestEpochSummary = summary
        }
    }

    // MARK: - Confirmation

    func resetConfirmation() {
        isConfirming = false
        confirmationBuffer.removeAll()
        updateConfirmationProgress("Idle")
    }

    func updateConfirmationProgress(_ status: String) {
        DispatchQueue.main.async {
            self.confirmationProgress = status
        }
        requestPersistedSessionSave()
    }
}
