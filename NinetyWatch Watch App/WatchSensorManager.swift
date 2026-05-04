import Foundation
import WatchKit
import HealthKit
import CoreMotion
import WatchConnectivity
import Combine
import CoreML

enum WatchConnectivityState {
    case synced
    case queued
    case watchOnly
}

enum WatchWeeklyAlarmSyncState: Equatable {
    case synced
    case saving
    case saved
    case pending
    case unreachable
    case failed
}

class WatchSensorManager: NSObject, ObservableObject, WKExtendedRuntimeSessionDelegate, WCSessionDelegate {
    static let pendingScheduleKey = "pendingSmartAlarmSchedule"
    static let readyScheduleKey = "readySmartAlarmSchedule"
    static let actualAlarmTimeKey = "actualSmartAlarmTime"
    static let localAlarmRecordKey = "watchLocalAlarmRecord"
    static let stopTombstoneKey = "watchAlarmStopTombstone"
    static let pendingNextAlarmCommandKey = "pendingNextAlarmCommand"
    static let pendingStopAlarmCommandKey = "pendingStopAlarmCommand"
    static let lastProcessedPhoneCommandSequenceKey = "lastProcessedPhoneCommandSequence"
    let payloadInterval: TimeInterval = 5
    let motionThreshold = 0.08
    let maxPendingPayloads = 12_000
    let backlogReplayBatchSize = 24
    let minimumBacklogFlushInterval: TimeInterval = 8
    let runtimeExpiryAlarmTolerance: TimeInterval = 10
    let epochDuration: TimeInterval = 30
    let minimumEpochsForFeatures = 5
    let smoothingWindowSize = 5
    let confirmationRequired = 3
    let confirmationThreshold = 2
    let maximumDynamicPredictionAge: TimeInterval = 90
    let monitoringLeadTime: TimeInterval = 30 * 60
    let alarmFinalMinuteBuffer: TimeInterval = 60

    enum WatchPipelineState: String, Codable {
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

    enum WatchSleepStage: Int, CaseIterable, Codable {
        case wake = 0
        case light = 1
        case deep = 2
        case rem = 3

        var title: String {
            switch self {
            case .wake: return "Wake"
            case .light: return "Light"
            case .deep: return "Deep"
            case .rem: return "REM"
            }
        }
    }

    struct WatchEpochAggregate {
        let timestamp: Date
        let heartRateMean: Double
        let heartRateStd: Double
        let heartRateRange: Double
        let motionMagMean: Double
        let motionMagMax: Double
        let motionJerk: Double
    }

    struct WatchPredictionSnapshot {
        let rawStage: WatchSleepStage
        let smoothedStage: WatchSleepStage
        let epoch: WatchEpochAggregate
        let isTestInjected: Bool
    }

    struct PendingPayloadEnvelope: Codable {
        let payload: SensorPayload
        let enqueuedAt: Date
        var lastAttemptAt: Date?
        var deliveryAttempts: Int
        var deferredDeliveryQueued: Bool
    }

    enum WatchLocalAlarmSyncState: String, Codable {
        case watchOnly
        case pending
        case synced
        case stopped
    }

    struct WatchLocalAlarmRecord: Codable, Equatable {
        let alarmInstanceID: UUID
        let weekday: Int
        let hour: Int
        let minute: Int
        let targetDate: Date
        let monitoringStartDate: Date
        let createdAt: Date
        var stoppedAt: Date?
        var syncState: WatchLocalAlarmSyncState
    }

    struct AlarmStopTombstone: Codable, Equatable {
        let alarmInstanceID: UUID?
        let targetDate: Date?
        let stoppedAt: Date
        let createdAt: Date?
    }

    struct PendingNextAlarmCommand: Codable, Equatable {
        let alarmInstanceID: UUID
        let weekday: Int
        let hour: Int
        let minute: Int
        let targetDate: Date
        let monitoringStartDate: Date
        let enqueuedAt: Date

        var message: [String: Any] {
            [
                "action": "setNextAlarm",
                "alarmInstanceID": alarmInstanceID.uuidString,
                "weekday": weekday,
                "hour": hour,
                "minute": minute,
                "targetDate": targetDate.timeIntervalSince1970,
                "monitoringStartDate": monitoringStartDate.timeIntervalSince1970,
                "createdAt": enqueuedAt.timeIntervalSince1970
            ]
        }

        init(record: WatchLocalAlarmRecord) {
            self.alarmInstanceID = record.alarmInstanceID
            self.weekday = record.weekday
            self.hour = record.hour
            self.minute = record.minute
            self.targetDate = record.targetDate
            self.monitoringStartDate = record.monitoringStartDate
            self.enqueuedAt = record.createdAt
        }
    }

    struct PendingStopAlarmCommand: Codable, Equatable {
        let alarmInstanceID: UUID?
        let targetDate: Date?
        let stoppedAt: Date
        let createdAt: Date?

        var message: [String: Any] {
            var message: [String: Any] = [
                "action": "stopAlarm",
                "stoppedAt": stoppedAt.timeIntervalSince1970
            ]
            if let alarmInstanceID {
                message["alarmInstanceID"] = alarmInstanceID.uuidString
            }
            if let targetDate {
                message["targetDate"] = targetDate.timeIntervalSince1970
            }
            if let createdAt {
                message["createdAt"] = createdAt.timeIntervalSince1970
            }
            return message
        }

        init(tombstone: AlarmStopTombstone) {
            self.alarmInstanceID = tombstone.alarmInstanceID
            self.targetDate = tombstone.targetDate
            self.stoppedAt = tombstone.stoppedAt
            self.createdAt = tombstone.createdAt
        }
    }
    
    static let shared = WatchSensorManager()
    
    @Published var sessionState: String = "Inactive"
    @Published var lastPayloadSent: String = "No data sent yet"
    @Published var connectionStatus: String = "Disconnected"
    @Published var isMocking: Bool = false
    @Published var nextAlarmDate: Date? = nil
    @Published var weeklyAlarmSyncState: WatchWeeklyAlarmSyncState = .synced
    @Published var weeklyAlarmSyncDetail: String? = nil
    
    var runtimeSession: WKExtendedRuntimeSession?
    var suppressNextRuntimeInvalidation = false
    let healthStore = HKHealthStore()
    let motionManager = CMMotionManager()
    var wcSession: WCSession?
    var pendingPayloads: [PendingPayloadEnvelope] = []
    var lastBacklogFlushDate: Date?
    var pipelineState: WatchPipelineState = .idle
    var replayStatusText: String = "No backlog activity"
    var isSendingNextAlarmCommand = false
    var alarmDeadlineTimer: Timer?
    var watchStageModel: MLModel?
    var currentEpochPayloads: [SensorPayload] = []
    var epochHistory: [WatchEpochAggregate] = []
    var rawPredictions: [WatchSleepStage] = []
    var confirmationBuffer: [WatchSleepStage] = []
    var isConfirmingSmartWake = false
    var smartWakeTriggered = false
    var localAnalysisStartDate: Date?
    var lastHRJumpEpochIndex = 0
    
    var hrQuery: HKAnchoredObjectQuery?
    var hrSamplesBuffer: [Double] = []
    var payloadTimer: AnyCancellable?
    var sensorsRunning = false
    
    // CoreMotion background anchors
    var motionDeviationSamples: [Double] = []
    var motionCountBuffer: Double = 0
    let motionQueue = OperationQueue()
    
    // For Mocking
    var mockTimer: AnyCancellable?
    
    override init() {
        super.init()
        restorePendingPayloadQueue()
        restorePendingNextAlarmCommand()
        restorePendingStopAlarmCommand()
        setupWatchConnectivity()
        refreshNextAlarmDate()
        loadWatchModel()
    }

    var hasPendingSchedule: Bool {
        pendingScheduledStartDate != nil
    }

    var pendingScheduleDescription: String? {
        guard let date = pendingScheduledStartDate else { return nil }
        return "Queued for \(date.formatted(date: .omitted, time: .shortened))"
    }

    var hasReadySchedule: Bool {
        readyScheduledStartDate != nil
    }

    var readyScheduleDescription: String? {
        guard let date = readyScheduledStartDate else { return nil }
        return "Ready for \(date.formatted(date: .omitted, time: .shortened))"
    }

    var connectivityState: WatchConnectivityState {
        guard let session = wcSession, WCSession.isSupported() else {
            return .watchOnly
        }

        guard session.activationState == .activated else {
            return .watchOnly
        }

        if session.isReachable {
            return .synced
        }

        return .queued
    }

    var isActivelyMonitoring: Bool {
        sensorsRunning ||
        runtimeSession?.state == .running ||
        pipelineState == .recording ||
        pipelineState == .deliveringBacklog
    }

    var hasUnsyncedLocalAlarm: Bool {
        guard let record = localAlarmRecord(), record.stoppedAt == nil else {
            return false
        }
        return record.syncState != .synced
    }


}
