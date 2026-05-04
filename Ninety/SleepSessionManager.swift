import Combine
import Foundation
import UIKit
import WatchConnectivity

final class SleepSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = SleepSessionManager()
    enum WatchCommandKey {
        static let sequence = "NinetyPhoneToWatchCommandSequence"
    }

    enum AlarmSyncKey {
        static let stopTombstone = "NinetyPhoneAlarmStopTombstone"
    }

    // MARK: - Sleep Stage Classification
    // Model output: 0=Wake, 1=N1/N2(light), 2=N3(deep), 3=REM
    enum SleepStage: Int, CaseIterable, Codable {
        case wake = 0
        case light = 1   // N1/N2 light sleep — TRIGGERS alarm
        case deep = 2    // N3 deep sleep — do NOT trigger
        case rem = 3     // REM — do NOT trigger

        var title: String {
            let preferredLang = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
            switch self {
            case .wake:
                return "Wake".localized(for: preferredLang)
            case .light:
                return "Light".localized(for: preferredLang)
            case .deep:
                return "Deep".localized(for: preferredLang)
            case .rem:
                return "REM".localized(for: preferredLang)
            }
        }
    }

    // MARK: - Per-Epoch Aggregate
    // Stores all raw data needed for feature engineering across rolling windows.
    struct EpochAggregate: Codable {
        let timestamp: Date
        let processedAt: Date?
        let heartRateMean: Double
        let heartRateStd: Double
        let heartRateRange: Double    // max - min of HR within epoch
        let motionMagMean: Double     // mean of motion counts in epoch
        let motionMagMax: Double      // max of motion counts in epoch
        let motionJerk: Double        // |current_motion - previous_motion|
        let modelStage: String?
        let isWatchTestInjected: Bool?
    }

    enum AnalysisSessionState: String, Codable {
        case idle
        case scheduled
        case recording
        case deliveringBacklog
        case completed
        case failed

        var label: String {
            switch self {
            case .idle:
                return "Idle"
            case .scheduled:
                return "Scheduled"
            case .recording:
                return "Recording"
            case .deliveringBacklog:
                return "Delivering backlog"
            case .completed:
                return "Completed"
            case .failed:
                return "Failed"
            }
        }
    }

    struct PersistedSessionState: Codable {
        let savedAt: Date
        let lastAcceptedPayloadAt: Date?
        let activeWakeTargetDate: Date?
        let sessionStartDate: Date?
        let sessionState: AnalysisSessionState
        let processedPayloadIDs: [UUID]
        let epochHistory: [EpochAggregate]
        let rawPredictionHistory: [SleepStage]
        let smoothedPredictionHistory: [SleepStage]
        let confirmationBuffer: [SleepStage]
        let isConfirming: Bool
        let lastPayloadReceived: String
        let watchStatus: String
        let watchConnectionStatus: String
        let watchQueuedStartDate: Date?
        let watchReadyStartDate: Date?
        let watchPendingPayloadCount: Int
        let replayStatus: String
        let ackStatus: String
        let engineLog: String
        let logs: [String]
        let modelStatus: String
        let rawStageDisplay: String
        let officialStageDisplay: String
        let latestEpochSummary: String
        let latestFeatureSummary: String
        let confirmationProgress: String
        let sessionRecoveryStatus: String
        let sessionStateDisplay: String
    }

    struct EpochDiagnosticsSnapshot: Identifiable {
        var id: Date { timestamp }

        let timestamp: Date
        let heartRateMean: Double
        let heartRateStd: Double
        let heartRateRange: Double
        let motionMagMean: Double
        let motionMagMax: Double
        let motionJerk: Double
        let modelStage: String
    }

    struct AlarmStopTombstone: Codable {
        let alarmInstanceID: UUID?
        let targetDate: Date?
        let stoppedAt: Date
        let createdAt: Date?
    }

    // MARK: - Configuration
    let maxTrackedPayloadIDs = 12_000
    let maxStoredPredictionHistory = 1_000
    let epochDuration: TimeInterval = 30
    let processingQueue = DispatchQueue(label: "Ninety.SleepSessionManager.processing")
    let persistenceQueue = DispatchQueue(label: "Ninety.SleepSessionManager.persistence")
    let processingQueueKey = DispatchSpecificKey<UInt8>()
    let processingQueueToken: UInt8 = 1
    let persistedSessionMaxAge: TimeInterval = 15 * 60
    let persistedScheduledSessionGrace: TimeInterval = 10 * 60

    // MARK: - Published UI State
    @Published var lastPayloadReceived: String = "No data received"
    @Published var watchStatus: String = "No watch session activity"
    @Published var watchConnectionStatus: String = "No connectivity status"
    @Published var watchQueuedStartDate: Date?
    @Published var watchReadyStartDate: Date?
    @Published var watchPendingPayloadCount: Int = 0
    @Published var replayStatus: String = "No backlog activity"
    @Published var ackStatus: String = "No acknowledgements yet"
    @Published var engineLog: String = "Idle"
    @Published var logs: [String] = []
    @Published var modelStatus: String = "Loading model"
    @Published var rawStageDisplay: String = "Warming up (5 epochs)"
    @Published var officialStageDisplay: String = "Warming up (5 epochs)"
    @Published var latestEpochSummary: String = "No 30-second epoch yet"
    @Published var latestFeatureSummary: String = "No features computed yet"
    @Published var confirmationProgress: String = "Idle"
    @Published var sessionRecoveryStatus: String = "Session restarted"
    @Published var sessionStateDisplay: String = "Idle"

    var isTrackingLive: Bool {
        sessionState == .recording || sessionState == .deliveringBacklog
    }

    var latestEpochDiagnostics: EpochDiagnosticsSnapshot? {
        performOnProcessingQueueSync {
            guard let epoch = epochHistory.last else { return nil }
                return EpochDiagnosticsSnapshot(
                    timestamp: epoch.timestamp,
                    heartRateMean: epoch.heartRateMean,
                    heartRateStd: epoch.heartRateStd,
                    heartRateRange: epoch.heartRateRange,
                    motionMagMean: epoch.motionMagMean,
                    motionMagMax: epoch.motionMagMax,
                    motionJerk: epoch.motionJerk,
                    modelStage: epoch.modelStage ?? smoothedPredictionHistory.last?.title ?? "-"
                )
        }
    }

    var recentEpochDiagnostics: [EpochDiagnosticsSnapshot] {
        performOnProcessingQueueSync {
            let offset = epochHistory.count - smoothedPredictionHistory.count
            return epochHistory.enumerated().reversed().map { index, epoch in
                var stageText: String
                let predIndex = index - offset
                if predIndex >= 0 && predIndex < smoothedPredictionHistory.count {
                    stageText = smoothedPredictionHistory[predIndex].title
                } else {
                    stageText = "-"
                }
                stageText = epoch.modelStage ?? stageText
                
                return EpochDiagnosticsSnapshot(
                    timestamp: epoch.timestamp,
                    heartRateMean: epoch.heartRateMean,
                    heartRateStd: epoch.heartRateStd,
                    heartRateRange: epoch.heartRateRange,
                    motionMagMean: epoch.motionMagMean,
                    motionMagMax: epoch.motionMagMax,
                    motionJerk: epoch.motionJerk,
                    modelStage: stageText
                )
            }
        }
    }

    // MARK: - Confirmation Window Configuration
    /// Number of predictions required in the confirmation window.
    let confirmationRequired = 3
    /// Minimum number of `.light` predictions within the window to confirm trigger.
    let confirmationThreshold = 2
    /// Accumulated predictions during the active confirmation window.
    var confirmationBuffer: [SleepStage] = []
    /// Whether a confirmation window is currently active.
    var isConfirming = false

    var preferredLang: String {
        UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
    }

    // MARK: - Internal State
    var wcSession: WCSession?
    var currentBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    var processedPayloadIDs: [UUID] = []
    var processedPayloadIDSet: Set<UUID> = []
    var processedWatchEpochDiagnosticIDs: [UUID] = []
    var processedWatchEpochDiagnosticIDSet: Set<UUID> = []
    var epochHistory: [EpochAggregate] = []
    var rawPredictionHistory: [SleepStage] = []
    var smoothedPredictionHistory: [SleepStage] = []
    var activeWakeTargetDate: Date?
    var sessionStartDate: Date?
    var lastAcceptedPayloadAt: Date?
    var lastWatchStatusTimestamp: TimeInterval = 0
    var sessionState: AnalysisSessionState = .idle

    override init() {
        super.init()
        processingQueue.setSpecific(key: processingQueueKey, value: processingQueueToken)
        setupWatchConnectivity()
        restorePersistedSessionIfValid()
        updateModelStatus("Watch-side model active")
    }


}
