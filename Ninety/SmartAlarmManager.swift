import Foundation
import Combine
import UserNotifications
import AVFoundation
import AppIntents

#if canImport(AlarmKit)
import AlarmKit
#endif

@MainActor
class SmartAlarmManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = SmartAlarmManager()
    nonisolated static let monitoringLeadTime: TimeInterval = 30 * 60

    struct ScheduledSleepSession {
        let wakeUpDate: Date
        let monitoringStartDate: Date
    }

    private enum StorageKey {
        static let stopTombstone = "NinetyAlarmStopTombstone"
    }

    private struct AlarmStopTombstone: Codable {
        let alarmInstanceID: UUID?
        let targetDate: Date?
        let stoppedAt: Date
        let createdAt: Date?
    }
    
    @Published var alarmStatus: String = "No alarms configured."
    @Published var monitoringCountdown: String = ""
    @Published var isWakeAlarmActive: Bool = false
    
    private var absoluteAlarmID: UUID?
    private var monitoringTimer: Timer?   // fires when the 30-minute tracking window opens
    private var countdownTimer: Timer?    // updates the countdown string every second
    private var wakeTargetDate: Date?
    private var alarmCreatedAt: Date?
    private let speechSynthesizer = AVSpeechSynthesizer()
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            await cleanupOrphanedSystemAlarmsIfNeeded()
        }
    }
    
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            SmartAlarmManager.shared.cancelSession()
        }
        completionHandler()
    }
    
    func requestPermissions(completion: @escaping (Bool) -> Void) {
        #if canImport(AlarmKit)
        Task {
            do {
                _ = try await AlarmManager.shared.requestAuthorization()
                self.alarmStatus = "AlarmKit Authorized"
                completion(true)
            } catch {
                self.alarmStatus = "AlarmKit Auth Failed: \(error)"
                completion(false)
            }
        }
        #else
        self.alarmStatus = "[Mock] AlarmKit Authorized (Not Available in this SDK)"
        completion(true)
        #endif
    }
    
#if canImport(AlarmKit)
    struct NinetyAlarmMetadata: AlarmMetadata {}
    
    private func createWakeAlarmAttributes() -> AlarmAttributes<NinetyAlarmMetadata> {
        let presentation = AlarmPresentation(
            alert: .init(title: "Ninety Wake Up")
        )
        return AlarmAttributes(presentation: presentation, tintColor: .blue)
    }
    #endif

    func scheduleSleepSession(endingAt requestedWakeUpDate: Date, alarmID: UUID? = nil, createdAt: Date? = nil) -> ScheduledSleepSession {
        let wakeUpDate = normalizedWakeUpDate(from: requestedWakeUpDate)
        let monitoringStartDate = monitoringStartDate(for: wakeUpDate)
        scheduleSystemAlarm(for: wakeUpDate, alarmID: alarmID, createdAt: createdAt)
        return ScheduledSleepSession(wakeUpDate: wakeUpDate, monitoringStartDate: monitoringStartDate)
    }
    
    func cancelSession(alarmID: UUID? = nil, stoppedAt: Date? = nil) {
        Task {
            await cancelSessionNow(alarmID: alarmID, stoppedAt: stoppedAt)
        }
    }

    func cancelSessionNow(alarmID: UUID? = nil, stoppedAt: Date? = nil) async {
        if let alarmID, let absoluteAlarmID, alarmID != absoluteAlarmID {
            let stopDate = stoppedAt ?? Date()
            recordStopTombstone(
                alarmID: alarmID,
                targetDate: nil,
                stoppedAt: stopDate,
                createdAt: nil
            )
            cancelSystemAlarm(id: alarmID)
            SleepSessionManager.shared.stopWatchAlarmPlayback(
                alarmID: alarmID,
                targetDate: nil,
                stoppedAt: stopDate
            )
            return
        }

        await clearScheduledSession(resetStatus: true, stoppedAt: stoppedAt ?? Date())
    }

    func rescheduleSystemAlarm(for targetDate: Date, alarmID: UUID? = nil, createdAt: Date? = nil) async {
        await clearScheduledSession(resetStatus: false)
        await scheduleSystemAlarmAfterClearing(for: targetDate, alarmID: alarmID, createdAt: createdAt)
    }

    private func clearScheduledSession(resetStatus: Bool, stoppedAt: Date? = nil) async {
        let cancelledAlarmID = absoluteAlarmID
        let cancelledTargetDate = wakeTargetDate
        let cancelledCreatedAt = alarmCreatedAt

        if let stoppedAt {
            recordStopTombstone(
                alarmID: cancelledAlarmID,
                targetDate: cancelledTargetDate,
                stoppedAt: stoppedAt,
                createdAt: cancelledCreatedAt
            )
        }

        monitoringTimer?.invalidate()
        monitoringTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        wakeTargetDate = nil
        alarmCreatedAt = nil
        monitoringCountdown = ""
        isWakeAlarmActive = false

        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

        cancelAllSystemAlarms()
        absoluteAlarmID = nil

        SleepSessionManager.shared.syncAlarmState(
            targetDate: nil,
            alarmID: cancelledAlarmID,
            createdAt: cancelledCreatedAt,
            stoppedAt: stoppedAt
        )
        if resetStatus || stoppedAt != nil {
            SleepSessionManager.shared.stopWatchAlarmPlayback(
                alarmID: cancelledAlarmID,
                targetDate: cancelledTargetDate,
                stoppedAt: stoppedAt
            )
        }
        SleepSessionManager.shared.pauseWatchMonitoring()

        if resetStatus {
            self.alarmStatus = "No alarms configured."
        }
    }
    
    func scheduleSystemAlarm(for targetDate: Date, alarmID: UUID? = nil, createdAt: Date? = nil) {
        Task {
            await rescheduleSystemAlarm(for: targetDate, alarmID: alarmID, createdAt: createdAt)
        }
    }

    private func scheduleSystemAlarmAfterClearing(for targetDate: Date, alarmID requestedAlarmID: UUID? = nil, createdAt requestedCreatedAt: Date? = nil) async {
        let alarmID = requestedAlarmID ?? UUID()
        let createdAt = requestedCreatedAt ?? Date()
        guard !shouldIgnoreScheduleDueToStop(alarmID: alarmID, targetDate: targetDate, createdAt: createdAt) else {
            self.alarmStatus = "Alarm ignored because it was already stopped."
            return
        }

        self.absoluteAlarmID = alarmID
        self.alarmCreatedAt = createdAt

        SleepSessionManager.shared.syncAlarmState(
            targetDate: targetDate,
            alarmID: alarmID,
            createdAt: createdAt
        )

        let monitoringStart = monitoringStartDate(for: targetDate)
        let now = Date()

        // Cancel any previous pending monitoring timer
        monitoringTimer?.invalidate()
        countdownTimer?.invalidate()
        wakeTargetDate = targetDate

        SleepSessionManager.shared.startWatchSession(
            targetDate: targetDate,
            alarmID: alarmID,
            createdAt: createdAt
        )

        if monitoringStart <= now {
            // We're already inside the 30-minute window — start immediately.
            self.alarmStatus = "Tracking window open on Apple Watch"
        } else {
            // The watch is armed immediately; the phone keeps a local countdown
            // so the user can still see when the monitoring window opens.
            let delay = monitoringStart.timeIntervalSinceNow
            self.alarmStatus = "Open Ninety on Apple Watch once before sleep to arm Smart Alarm"

            // Live countdown
            countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { return }
                let remaining = monitoringStart.timeIntervalSinceNow
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if remaining <= 0 {
                        self.countdownTimer?.invalidate()
                        self.monitoringCountdown = ""
                    } else {
                        let mins = Int(remaining) / 60
                        let secs = Int(remaining) % 60
                        self.monitoringCountdown = String(format: "Monitoring in %02d:%02d", mins, secs)
                    }
                }
            }

            // Schedule Watch session start
            monitoringTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.alarmStatus = "🟢 Tracking window open on Apple Watch"
                    self.monitoringCountdown = ""
                }
            }
        }

        self.alarmStatus = monitoringStart <= now
            ? "🟢 Watch monitoring armed | AlarmKit fallback set: \(targetDate.formatted(date: .omitted, time: .shortened))"
            : "⏳ AlarmKit fallback set: \(targetDate.formatted(date: .omitted, time: .shortened)) | Open Watch once before sleep"

        #if canImport(AlarmKit)
        do {
            let configuration = AlarmManager.AlarmConfiguration(
                schedule: .fixed(targetDate),
                attributes: createWakeAlarmAttributes(),
                stopIntent: StopNinetyWakeAlarmIntent()
            )
            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
            self.alarmStatus = self.alarmStatus.contains("🟢")
                ? "🟢 Watch monitoring armed | ✅ AlarmKit fallback set: \(targetDate.formatted(date: .omitted, time: .shortened))"
                : "⏳ ✅ AlarmKit fallback set: \(targetDate.formatted(date: .omitted, time: .shortened)) | Open Watch once before sleep"
        } catch {
            self.alarmStatus = "System Alarm Schedule failed: \(error)"
        }
        #else
        self.alarmStatus = "[Sim] AlarmKit fallback set: \(targetDate.formatted(date: .omitted, time: .shortened)) | Open Watch once before sleep"
        #endif
    }

    func currentAlarmInstanceID() -> UUID? {
        absoluteAlarmID
    }

    private func stopTombstone() -> AlarmStopTombstone? {
        guard let data = UserDefaults.standard.data(forKey: StorageKey.stopTombstone) else {
            return nil
        }

        guard let tombstone = try? JSONDecoder().decode(AlarmStopTombstone.self, from: data) else {
            UserDefaults.standard.removeObject(forKey: StorageKey.stopTombstone)
            return nil
        }

        return tombstone
    }

    private func recordStopTombstone(alarmID: UUID?, targetDate: Date?, stoppedAt: Date, createdAt: Date?) {
        let tombstone = AlarmStopTombstone(
            alarmInstanceID: alarmID,
            targetDate: targetDate,
            stoppedAt: stoppedAt,
            createdAt: createdAt
        )

        if let existing = stopTombstone(), existing.stoppedAt > stoppedAt {
            return
        }

        guard let data = try? JSONEncoder().encode(tombstone) else { return }
        UserDefaults.standard.set(data, forKey: StorageKey.stopTombstone)
    }

    private func shouldIgnoreScheduleDueToStop(alarmID: UUID, targetDate: Date, createdAt: Date) -> Bool {
        guard let tombstone = stopTombstone() else { return false }
        guard tombstone.stoppedAt >= createdAt else { return false }

        if let stoppedID = tombstone.alarmInstanceID, stoppedID == alarmID {
            return true
        }

        if let stoppedTarget = tombstone.targetDate, abs(stoppedTarget.timeIntervalSince(targetDate)) < 1 {
            return true
        }

        return false
    }

    private func cleanupOrphanedSystemAlarmsIfNeeded() async {
        let scheduleViewModel = ScheduleViewModel(observesExternalChanges: false)
        guard scheduleViewModel.nextUpcomingSession == nil else { return }
        await clearScheduledSession(resetStatus: true)
    }

    private func cancelAllSystemAlarms() {
        #if canImport(AlarmKit)
        let trackedAlarmIDs = Set((try? AlarmManager.shared.alarms.map(\.id)) ?? [])
        for alarmID in trackedAlarmIDs {
            try? AlarmManager.shared.cancel(id: alarmID)
        }
        #endif
    }

    private func cancelSystemAlarm(id alarmID: UUID) {
        #if canImport(AlarmKit)
        try? AlarmManager.shared.cancel(id: alarmID)
        #endif
    }
    
    // MARK: - Post-Alarm Feedback
    
    func playPostAlarmFeedback(minutesSaved: Int) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            
            let message = "Buongiorno, ti ho svegliato \(minutesSaved) minuti prima del tuo limite massimo perché il tuo ciclo era al picco di efficienza."
            let utterance = AVSpeechUtterance(string: message)
            
            // Prefer an Italian voice since the dialog is in Italian.
            if let voice = AVSpeechSynthesisVoice(language: "it-IT") {
                utterance.voice = voice
            }
            
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utterance.volume = 1.0
            
            speechSynthesizer.speak(utterance)
        } catch {
            print("Failed to configure audio session for post-alarm feedback: \(error)")
        }
    }

    private func normalizedWakeUpDate(from requestedWakeUpDate: Date) -> Date {
        guard requestedWakeUpDate <= Date() else {
            return requestedWakeUpDate
        }

        return Calendar.current.date(byAdding: .day, value: 1, to: requestedWakeUpDate) ?? requestedWakeUpDate
    }

    private func monitoringStartDate(for wakeUpDate: Date) -> Date {
        wakeUpDate.addingTimeInterval(-Self.monitoringLeadTime)
    }
}
