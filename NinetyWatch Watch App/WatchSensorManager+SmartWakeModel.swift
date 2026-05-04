import Foundation
import WatchKit
import HealthKit
import CoreMotion
import WatchConnectivity
import Combine
import CoreML

extension WatchSensorManager {
    // MARK: - Watch-Local Smart Alarm Model

    func loadWatchModel() {
        guard let modelURL = Bundle.main.url(forResource: "NeuralWakeUP", withExtension: "mlmodelc") else {
            replayStatusText = "Watch ML missing"
            return
        }

        do {
            let configuration = MLModelConfiguration()
            watchStageModel = try MLModel(contentsOf: modelURL, configuration: configuration)
            replayStatusText = "Watch ML ready"
        } catch {
            replayStatusText = "Watch ML failed: \(error.localizedDescription)"
        }
    }

    func resetLocalAnalysis(startDate: Date? = nil) {
        currentEpochPayloads.removeAll()
        epochHistory.removeAll()
        rawPredictions.removeAll()
        confirmationBuffer.removeAll()
        isConfirmingSmartWake = false
        smartWakeTriggered = false
        lastHRJumpEpochIndex = 0
        localAnalysisStartDate = startDate
    }

    func processPayloadForLocalSmartWake(_ payload: SensorPayload) {
        guard !smartWakeTriggered else { return }
        guard let targetDate = currentAlarmTargetDate(), payload.timestamp < targetDate else { return }

        if let lastTimestamp = currentEpochPayloads.last?.timestamp ?? epochHistory.last?.timestamp {
            let gap = payload.timestamp.timeIntervalSince(lastTimestamp)
            if gap > 300 {
                resetLocalAnalysis(startDate: Date())
            }
        }

        currentEpochPayloads.append(payload)
        let epochStart = currentEpochPayloads.first?.timestamp ?? payload.timestamp
        guard payload.timestamp.timeIntervalSince(epochStart) >= epochDuration else {
            return
        }

        let hrValues = currentEpochPayloads.flatMap(\.hrSamples)
        var hrMean = hrValues.isEmpty ? 0 : hrValues.reduce(0, +) / Double(hrValues.count)
        var hrStd = standardDeviation(for: hrValues)
        var hrRange = hrValues.isEmpty ? 0 : (hrValues.max()! - hrValues.min()!)

        if hrMean < 30 {
            if let previousEpoch = epochHistory.last {
                hrMean = previousEpoch.heartRateMean
                hrStd = previousEpoch.heartRateStd
                hrRange = previousEpoch.heartRateRange
            } else {
                hrMean = 60
                hrStd = 0
                hrRange = 0
            }
        }

        let motionValues = currentEpochPayloads.map(\.motionCount)
        let motionMagMean = motionValues.reduce(0, +) / max(Double(motionValues.count), 1)
        let motionMagMax = motionValues.max() ?? 0
        let previousMotion = epochHistory.last?.motionMagMean ?? motionMagMean
        let motionJerk = abs(motionMagMean - previousMotion)

        let epoch = WatchEpochAggregate(
            timestamp: payload.timestamp,
            heartRateMean: hrMean,
            heartRateStd: hrStd,
            heartRateRange: hrRange,
            motionMagMean: motionMagMean,
            motionMagMax: motionMagMax,
            motionJerk: motionJerk
        )

        currentEpochPayloads.removeAll()
        epochHistory.append(epoch)

        if epochHistory.count >= 2 {
            let previousHR = epochHistory[epochHistory.count - 2].heartRateMean
            if abs(epoch.heartRateMean - previousHR) > 5 {
                lastHRJumpEpochIndex = epochHistory.count - 1
            }
        }

        guard epochHistory.count >= minimumEpochsForFeatures else {
            updatePipelineState(.recording, detail: "Watch ML warming \(epochHistory.count)/\(minimumEpochsForFeatures)")
            sendWatchEpochDiagnostic(
                for: epoch,
                rawStage: nil,
                smoothedStage: nil,
                stageTitle: "Warming \(epochHistory.count)/\(minimumEpochsForFeatures)",
                isTestInjected: false
            )
            return
        }

        guard let prediction = makeWatchPrediction(forEpochAt: epochHistory.count - 1) else {
            sendWatchEpochDiagnostic(
                for: epoch,
                rawStage: nil,
                smoothedStage: nil,
                stageTitle: "Unavailable",
                isTestInjected: false
            )
            return
        }

        sendWatchEpochDiagnostic(
            for: prediction.epoch,
            rawStage: prediction.rawStage,
            smoothedStage: prediction.smoothedStage,
            stageTitle: prediction.smoothedStage.title,
            isTestInjected: prediction.isTestInjected
        )
        updatePipelineState(.recording, detail: "Watch ML \(prediction.smoothedStage.title)")
        evaluateLocalSmartWake(for: prediction, targetDate: targetDate)
    }

    func makeWatchPrediction(forEpochAt index: Int) -> WatchPredictionSnapshot? {
        guard let watchStageModel else {
            replayStatusText = "Watch ML unavailable"
            return nil
        }

        let features = computeWatchFeatures(forEpochAt: index)
        let epoch = epochHistory[index]

        do {
            let input = features.mapValues { NSNumber(value: $0) }
            let provider = try MLDictionaryFeatureProvider(dictionary: input)
            let prediction = try watchStageModel.prediction(from: provider)

            guard
                let rawValue = prediction.featureValue(for: "target")?.int64Value,
                let rawStage = WatchSleepStage(rawValue: Int(rawValue))
            else {
                replayStatusText = "Watch ML output missing"
                return nil
            }

            rawPredictions.append(rawStage)
            if rawPredictions.count > smoothingWindowSize {
                rawPredictions.removeFirst(rawPredictions.count - smoothingWindowSize)
            }

            let smoothedStage = modeStage(from: rawPredictions) ?? rawStage
            replayStatusText = "Watch ML raw \(rawStage.title), smooth \(smoothedStage.title)"
            return WatchPredictionSnapshot(
                rawStage: rawStage,
                smoothedStage: smoothedStage,
                epoch: epoch,
                isTestInjected: false
            )
        } catch {
            replayStatusText = "Watch ML prediction failed: \(error.localizedDescription)"
            return nil
        }
    }

    func evaluateLocalSmartWake(for prediction: WatchPredictionSnapshot, targetDate: Date) {
        guard !smartWakeTriggered else { return }
        guard localSmartWakeCanTrigger(for: prediction, targetDate: targetDate) else { return }

        if prediction.smoothedStage == .light {
            if !isConfirmingSmartWake {
                isConfirmingSmartWake = true
                confirmationBuffer.removeAll()
            }

            confirmationBuffer.append(prediction.smoothedStage)
        } else if isConfirmingSmartWake {
            confirmationBuffer.append(prediction.smoothedStage)
        } else {
            return
        }

        let progress = "\(confirmationBuffer.count)/\(confirmationRequired)"
        updatePipelineState(.recording, detail: "Watch ML verify \(progress)")

        guard confirmationBuffer.count >= confirmationRequired else { return }

        let lightCount = confirmationBuffer.filter { $0 == .light }.count
        if lightCount >= confirmationThreshold {
            smartWakeTriggered = true
            triggerLocalSmartWake(reason: "Smart Wake (Watch ML \(lightCount)/\(confirmationRequired))")
        } else {
            confirmationBuffer.removeAll()
            isConfirmingSmartWake = false
        }
    }

    func sendWatchEpochDiagnostic(
        for epoch: WatchEpochAggregate,
        rawStage: WatchSleepStage?,
        smoothedStage: WatchSleepStage?,
        stageTitle: String,
        isTestInjected: Bool
    ) {
        guard let session = wcSession, session.activationState == .activated else { return }

        let diagnostic = WatchEpochDiagnostic(
            id: UUID(),
            timestamp: epoch.timestamp,
            processedAt: Date(),
            heartRateMean: epoch.heartRateMean,
            heartRateStd: epoch.heartRateStd,
            heartRateRange: epoch.heartRateRange,
            motionMagMean: epoch.motionMagMean,
            motionMagMax: epoch.motionMagMax,
            motionJerk: epoch.motionJerk,
            rawStage: rawStage?.rawValue,
            smoothedStage: smoothedStage?.rawValue,
            stageTitle: stageTitle,
            isTestInjected: isTestInjected
        )

        guard let encoded = try? JSONEncoder().encode(diagnostic) else { return }

        let message: [String: Any] = [
            "action": "watchEpochDiagnostic",
            "watchEpochData": encoded
        ]

        session.transferUserInfo(message)
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        }
    }

    func localSmartWakeCanTrigger(for prediction: WatchPredictionSnapshot, targetDate: Date) -> Bool {
        let now = Date()
        guard now < targetDate else { return false }
        guard now < targetDate.addingTimeInterval(-alarmFinalMinuteBuffer) else {
            confirmationBuffer.removeAll()
            isConfirmingSmartWake = false
            return false
        }

        let predictionAge = max(0, now.timeIntervalSince(prediction.epoch.timestamp))
        guard predictionAge <= maximumDynamicPredictionAge else {
            confirmationBuffer.removeAll()
            isConfirmingSmartWake = false
            return false
        }

        return true
    }

    func triggerLocalSmartWake(reason: String) {
        startWatchHapticWakePhase()
        
        // Tell the phone to start the same Ninety alarm.
        sendTriggerAlarmMessage()
        
        clearScheduledAlarmAndMonitoring(
            detail: reason,
            state: .completed,
            keepHapticsRunning: true
        )
    }

    func startWatchHapticWakePhase() {
        HapticWakeUpManager.shared.startGradualWakeUp()
    }

    func currentAlarmTargetDate() -> Date? {
        if let nextAlarmDate {
            return nextAlarmDate
        }

        guard let interval = UserDefaults.standard.object(forKey: Self.actualAlarmTimeKey) as? TimeInterval else {
            return nil
        }

        let storedDate = Date(timeIntervalSince1970: interval)
        return storedDate > Date() ? storedDate : nil
    }

    func nextLocalAlarmTargetDate(hour: Int, minute: Int, now: Date = Date()) -> Date? {
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

    func scheduledMonitoringStartDate(for targetDate: Date) -> Date {
        let requestedStart = targetDate.addingTimeInterval(-monitoringLeadTime)
        if requestedStart <= Date() {
            return Date().addingTimeInterval(2)
        }
        return requestedStart
    }

    func createPaddedWindow(endIndex: Int, requiredCount: Int) -> [WatchEpochAggregate] {
        let availableCount = endIndex + 1
        var window = Array(epochHistory[max(0, endIndex - requiredCount + 1)...endIndex])

        if availableCount < requiredCount, let earliestKnown = window.first {
            let paddingCount = requiredCount - availableCount
            window = Array(repeating: earliestKnown, count: paddingCount) + window
        }

        return window
    }

    func computeWatchFeatures(forEpochAt index: Int) -> [String: Double] {
        let epoch = epochHistory[index]

        let epochs2m = createPaddedWindow(endIndex: index, requiredCount: 4)
        let epochs5m = createPaddedWindow(endIndex: index, requiredCount: 10)
        let epochs10m = createPaddedWindow(endIndex: index, requiredCount: 20)

        let motionMags2m = epochs2m.map(\.motionMagMean)
        let motionMags5m = epochs5m.map(\.motionMagMean)
        let motionMags10m = epochs10m.map(\.motionMagMean)
        let jerk5m = epochs5m.map(\.motionJerk)

        let hrMeans5m = epochs5m.map(\.heartRateMean)
        let hrMeans10m = epochs10m.map(\.heartRateMean)
        let hrStds5m = epochs5m.map(\.heartRateStd)
        let hrRanges5m = epochs5m.map(\.heartRateRange)

        let motionEpochMagMean = epoch.motionMagMean
        let motionEpochMagMax = epoch.motionMagMax

        let motionHist2mMagMean = mean(of: motionMags2m)
        let motionHist2mMagStd = standardDeviation(for: motionMags2m)
        let motionHist5mMagMean = mean(of: motionMags5m)
        let motionHist5mMagStd = standardDeviation(for: motionMags5m)
        let motionHist5mMagMax = motionMags5m.max() ?? 0
        let motionHist5mMagSum = motionMags5m.reduce(0, +)
        let motionHist10mMagMean = mean(of: motionMags10m)
        let motionHist10mMagStd = standardDeviation(for: motionMags10m)
        let motionHist5mJerkStd = standardDeviation(for: jerk5m)

        let motionEpochJerkMinusHist5mMean = epoch.motionJerk - mean(of: jerk5m)
        let motionEpochMagMinusHist5mMean = motionEpochMagMean - motionHist5mMagMean
        let motionEpochMagMinusHist2mMean = motionEpochMagMean - motionHist2mMagMean

        let hrHist5mMean = mean(of: hrMeans5m)
        let hrHist5mStd = standardDeviation(for: hrMeans5m)
        let hrHist10mMean = mean(of: hrMeans10m)
        let hrHist10mStd = standardDeviation(for: hrMeans10m)
        let hrHist5mCV = hrHist5mMean > 0 ? hrHist5mStd / hrHist5mMean : 0
        let hrHist10mCV = hrHist10mMean > 0 ? hrHist10mStd / hrHist10mMean : 0

        let hrEpochRangeMinusHist5mRange = epoch.heartRateRange - mean(of: hrRanges5m)
        let hrEpochStdMinusHist5mStd = epoch.heartRateStd - mean(of: hrStds5m)
        let hrEpochMeanDivHist10mMean = hrHist10mMean > 0 ? epoch.heartRateMean / hrHist10mMean : 1

        let startDate = localAnalysisStartDate ?? epochHistory.first?.timestamp ?? epoch.timestamp
        let elapsedMinutes = epoch.timestamp.timeIntervalSince(startDate) / 60
        let timeHoursFromStart = elapsedMinutes / 60
        let minutesSinceJump = Double(index - lastHRJumpEpochIndex) * 0.5

        return [
            "motion_hist5m_mag_max_log1p": log1p(motionHist5mMagMax),
            "motion_hist10m_mag_std_log1p": log1p(motionHist10mMagStd),
            "motion_hist5m_jerk_std_log1p": log1p(motionHist5mJerkStd),
            "motion_hist5m_mag_std_log1p": log1p(motionHist5mMagStd),
            "hr_hist10m_cv_raw": hrHist10mCV,
            "hr_hist5m_cv_raw": hrHist5mCV,
            "hr_hist10m_std_raw": hrHist10mStd,
            "hr_hist5m_std_raw": hrHist5mStd,
            "minutes_since_last_hr_jump_log1p": log1p(minutesSinceJump),
            "time_hours_from_start": timeHoursFromStart,
            "elapsed_minutes_log1p": log1p(elapsedMinutes),
            "motion_hist10m_mag_mean_log1p": log1p(motionHist10mMagMean),
            "motion_epoch_jerk_minus_hist5m_mean": motionEpochJerkMinusHist5mMean,
            "motion_hist5m_mag_mean_log1p": log1p(motionHist5mMagMean),
            "motion_hist5m_mag_sum_log1p": log1p(motionHist5mMagSum),
            "motion_epoch_mag_minus_hist5m_mean": motionEpochMagMinusHist5mMean,
            "motion_hist2m_mag_std_log1p": log1p(motionHist2mMagStd),
            "motion_hist2m_mag_mean_log1p": log1p(motionHist2mMagMean),
            "hr_epoch_range_minus_hist5m_range": hrEpochRangeMinusHist5mRange,
            "motion_epoch_mag_mean_log1p": log1p(motionEpochMagMean),
            "hr_epoch_std_minus_hist5m_std": hrEpochStdMinusHist5mStd,
            "hr_epoch_mean_div_hist10m_mean": hrEpochMeanDivHist10mMean,
            "motion_epoch_mag_minus_hist2m_mean": motionEpochMagMinusHist2mMean,
            "hr_hist10m_mean_raw": hrHist10mMean,
            "motion_epoch_mag_max_log1p": log1p(motionEpochMagMax)
        ]
    }

    func modeStage(from values: [WatchSleepStage]) -> WatchSleepStage? {
        guard !values.isEmpty else { return nil }

        let counts = Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
        let maxCount = counts.values.max() ?? 0
        let candidates = counts.compactMap { stage, count in
            count == maxCount ? stage : nil
        }

        for stage in values.reversed() where candidates.contains(stage) {
            return stage
        }

        return values.last
    }

    func mean(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
    
}
