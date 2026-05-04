import Foundation
import SwiftUI

@MainActor
final class ScheduleViewModel: ObservableObject {
    enum StorageKey {
        static let wakeTime = "scheduleWakeTimeInterval"
        static let wakeTimesDict = "scheduleWakeTimesDict"
        static let scheduledWeekdays = "scheduleWeekdayPlan"
        static let weekdayMutationTimes = "scheduleWeekdayMutationTimes"
    }

    static let externalScheduleDidChangeNotification = Notification.Name("NinetyExternalScheduleDidChange")
    static let externalScheduleChangedWeekdayKey = "weekday"

    struct WeeklyAlarmSnapshot {
        let weekday: Int
        let hour: Int
        let minute: Int
        let wakeUpDate: Date

        var session: SmartAlarmManager.ScheduledSleepSession {
            SmartAlarmManager.ScheduledSleepSession(
                wakeUpDate: wakeUpDate,
                monitoringStartDate: wakeUpDate.addingTimeInterval(-SmartAlarmManager.monitoringLeadTime)
            )
        }
    }

    struct WeeklyAlarmOperationResult {
        let affectedAlarm: WeeklyAlarmSnapshot?
        let nextAlarm: WeeklyAlarmSnapshot?
        let didScheduleSystemAlarm: Bool
    }

    struct WatchWeeklyAlarmApplyResult {
        let affectedAlarm: WeeklyAlarmSnapshot?
        let nextAlarm: WeeklyAlarmSnapshot?
        let didScheduleSystemAlarm: Bool
        let didApply: Bool
        let isStale: Bool
    }

    enum WeeklyAlarmError: LocalizedError {
        case invalidWeekday
        case invalidTime
        case invalidOffset
        case inactiveWeekday
        case crossesDayBoundary

        var errorDescription: String? {
            switch self {
            case .invalidWeekday:
                return "Quel giorno non è valido."
            case .invalidTime:
                return "Quell'orario non è valido."
            case .invalidOffset:
                return "Dimmi di quanti minuti vuoi spostare la sveglia."
            case .inactiveWeekday:
                return "Non hai nessuna sveglia Ninety attiva per quel giorno."
            case .crossesDayBoundary:
                return "Questo spostamento cambierebbe giorno. Imposta direttamente la sveglia sul nuovo giorno corretto."
            }
        }
    }

    @Published var wakeTimes: [String: TimeInterval] {
        didSet {
            UserDefaults.standard.set(wakeTimes, forKey: StorageKey.wakeTimesDict)
        }
    }
    
    @Published var selectedWeekday: Int = Calendar.current.component(.weekday, from: Date()) {
        didSet {
            logClock("selectedWeekday DID SET to: \(selectedWeekday)")
            updateCurrentWakeUpTime()
        }
    }
    
    @Published var currentWakeUpTime: Date
    @Published var scheduledWeekdays: Set<Int> {
        didSet {
            UserDefaults.standard.set(Array(scheduledWeekdays).sorted(), forKey: StorageKey.scheduledWeekdays)
        }
    }
    @Published var weekdayMutationTimes: [String: TimeInterval] {
        didSet {
            UserDefaults.standard.set(weekdayMutationTimes, forKey: StorageKey.weekdayMutationTimes)
        }
    }
    @Published var lastScheduledSession: SmartAlarmManager.ScheduledSleepSession?
    @Published var isScheduling = false
    @Published var schedulingError: String?
    @Published var selectedDayHour: Int = 7
    @Published var selectedDayMinute: Int = 0
    @Published var clockLogs: [String] = []
    var externalScheduleObserver: NSObjectProtocol?
    
    func logClock(_ msg: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timeString = formatter.string(from: Date())
        let fullMsg = "[\(timeString)] \(msg)"
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.clockLogs.append(fullMsg)
            if self.clockLogs.count > 100 {
                self.clockLogs.removeFirst(self.clockLogs.count - 100)
            }
            print(fullMsg)
        }
    }

    init(observesExternalChanges: Bool = true) {
        wakeTimes = Self.loadWakeTimesFromStorage()
        currentWakeUpTime = ScheduleViewModel.defaultWakeTime

        self.scheduledWeekdays = Self.loadScheduledWeekdaysFromStorage()
        self.weekdayMutationTimes = Self.loadWeekdayMutationTimesFromStorage()
        
        lastScheduledSession = nil
        if observesExternalChanges {
            observeExternalScheduleChanges()
        }
        logClock("INIT ViewModel finished.")
        updateCurrentWakeUpTime()
        lastScheduledSession = nextUpcomingSession
    }

    deinit {
        if let externalScheduleObserver {
            NotificationCenter.default.removeObserver(externalScheduleObserver)
        }
    }

    static var defaultWakeTime: Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 7
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components) ?? .now
    }

    var isAlarmEnabled: Bool {
        !scheduledWeekdays.isEmpty
    }

    var isAlarmEnabledForSelectedDay: Bool {
        scheduledWeekdays.contains(selectedWeekday)
    }

    var projectedSession: SmartAlarmManager.ScheduledSleepSession {
        nextUpcomingSession ?? fallbackProjectedSession
    }

    var nextUpcomingSession: SmartAlarmManager.ScheduledSleepSession? {
        nextUpcomingAlarm?.session
    }

    var nextUpcomingAlarm: WeeklyAlarmSnapshot? {
        scheduledWeekdays.compactMap { alarmSnapshot(for: $0) }.min {
            $0.wakeUpDate < $1.wakeUpDate
        }
    }

    var wakeTimeLabel: String {
        currentWakeUpTime.formatted(date: .omitted, time: .shortened)
    }

    var scheduledDayLabel: String {
        let preferredLang = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        guard let wakeUpDate = nextUpcomingSession?.wakeUpDate else {
            return "Pick your days".localized(for: preferredLang)
        }
        if Calendar.current.isDateInToday(wakeUpDate) {
            return "Today".localized(for: preferredLang)
        }
        if Calendar.current.isDateInTomorrow(wakeUpDate) {
            return "Tomorrow".localized(for: preferredLang)
        }
        let locale = Locale(identifier: preferredLang)
        return wakeUpDate.formatted(.dateTime.weekday(.wide).locale(locale))
    }

    var nextUpcomingLabel: String {
        let preferredLang = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        guard let session = nextUpcomingSession else {
            return "No days selected".localized(for: preferredLang)
        }
        let locale = Locale(identifier: preferredLang)
        let day = session.wakeUpDate.formatted(.dateTime.weekday(.abbreviated).locale(locale))
        let time = session.wakeUpDate.formatted(Date.FormatStyle().locale(locale).hour().minute())
        return "\(day) · \(time)"
    }

    var primaryButtonTitle: String {
        let preferredLang = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        guard !isScheduling else {
            return "Updating Plan...".localized(for: preferredLang)
        }
        guard nextUpcomingSession != nil else {
            return "Choose Days to Plan".localized(for: preferredLang)
        }
        return "\("Next Up".localized(for: preferredLang)) · \(nextUpcomingLabel)"
    }

    @discardableResult
    func scheduleSession(alarmID: UUID? = nil, createdAt: Date? = nil) async -> Bool {
        guard !isScheduling else { return false }
        guard let nextUpcomingSession else {
            await SmartAlarmManager.shared.cancelSessionNow()
            lastScheduledSession = nil
            schedulingError = nil
            return true
        }

        isScheduling = true
        schedulingError = nil
        defer { isScheduling = false }

        let granted = await requestAlarmPermissions()
        guard granted else {
            let preferredLang = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
            schedulingError = "Permissions are required to schedule your weekly wake-up plan.".localized(for: preferredLang)
            return false
        }

        await SmartAlarmManager.shared.rescheduleSystemAlarm(
            for: nextUpcomingSession.wakeUpDate,
            alarmID: alarmID,
            createdAt: createdAt
        )
        lastScheduledSession = nextUpcomingSession
        return true
    }

    func cancelSession() {
        SleepSessionManager.shared.log("UI Interaction: Cancelled system scheduled session")
        SmartAlarmManager.shared.cancelSession()
        lastScheduledSession = nil
    }

    func toggleScheduledWeekday(_ weekday: Int) {
        if scheduledWeekdays.contains(weekday) {
            scheduledWeekdays.remove(weekday)
        } else {
            scheduledWeekdays.insert(weekday)
        }
        markMutation(for: weekday)

        lastScheduledSession = nextUpcomingSession

        SleepSessionManager.shared.log("UI Interaction: Toggled alarm for weekday \(weekday). Active: \(scheduledWeekdays.contains(weekday))")

        Task {
            if scheduledWeekdays.isEmpty {
                cancelSession()
            } else {
                await scheduleSession()
            }
        }
    }
    
    func toggleSelectedDay() {
        toggleScheduledWeekday(selectedWeekday)
    }

    func updateWakeTime(hour: Int, minute: Int) {
        logClock("updateWakeTime CALLED with \(hour):\(minute) for weekday \(selectedWeekday)")
        storeWakeTime(weekday: selectedWeekday, hour: hour, minute: minute)
        markMutation(for: selectedWeekday)
        
        SleepSessionManager.shared.log("UI Interaction: Updated wake time to \(String(format: "%02d:%02d", hour, minute)) for weekday \(selectedWeekday)")
        logClock("wakeTimes[\(selectedWeekday)] updated to \(wakeTimes[String(selectedWeekday)]!)")
        
        lastScheduledSession = nextUpcomingSession

        guard scheduledWeekdays.contains(selectedWeekday) else {
            return
        }

        Task {
            await scheduleSession()
        }
    }
    
    func updateCurrentWakeUpTime() {
        let key = String(selectedWeekday)
        let totalSeconds = (wakeTimes[key] ?? TimeInterval(7 * 3600)).rounded()
        let totalSecondsInt = Int(totalSeconds)
        
        let h = totalSecondsInt / 3600
        let m = (totalSecondsInt % 3600) / 60
        
        logClock("updateCurrentWakeUpTime CALLED for key \(key). Computed: \(h):\(m). WakeTimes Dict: \(wakeTimes)")
        
        selectedDayHour = h
        selectedDayMinute = m
        currentWakeUpTime = Self.todayDate(hour: h, minute: m)
    }

    /// Builds a Date for today at the given hour and minute.
    static func todayDate(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components) ?? .now
    }

    func setWeeklyAlarm(weekday: Int, wakeTime: Date) async throws -> WeeklyAlarmOperationResult {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: wakeTime)
        let minute = calendar.component(.minute, from: wakeTime)
        return try await setWeeklyAlarm(weekday: weekday, hour: hour, minute: minute)
    }

    func setWeeklyAlarm(weekday: Int, hour: Int, minute: Int) async throws -> WeeklyAlarmOperationResult {
        try validate(weekday: weekday, hour: hour, minute: minute)

        storeWakeTime(weekday: weekday, hour: hour, minute: minute)
        scheduledWeekdays.insert(weekday)
        markMutation(for: weekday)
        lastScheduledSession = nextUpcomingSession

        SleepSessionManager.shared.log("Siri: Set weekly alarm for weekday \(weekday) at \(String(format: "%02d:%02d", hour, minute))")

        let didSchedule = await scheduleSession()
        return WeeklyAlarmOperationResult(
            affectedAlarm: alarmSnapshot(for: weekday),
            nextAlarm: nextUpcomingAlarm,
            didScheduleSystemAlarm: didSchedule
        )
    }

    func applyWatchWeeklyAlarm(weekday: Int, hour: Int, minute: Int, createdAt: Date, alarmID: UUID? = nil) async throws -> WatchWeeklyAlarmApplyResult {
        try validate(weekday: weekday, hour: hour, minute: minute)

        let createdAtInterval = createdAt.timeIntervalSince1970
        let latestMutationInterval = mutationTime(for: weekday)
        guard createdAtInterval >= latestMutationInterval else {
            let nextAlarm = nextUpcomingAlarm
            SleepSessionManager.shared.log(
                "Watch UI: Ignored stale weekly alarm for weekday \(weekday) at \(String(format: "%02d:%02d", hour, minute))"
            )
            return WatchWeeklyAlarmApplyResult(
                affectedAlarm: alarmSnapshot(for: weekday),
                nextAlarm: nextAlarm,
                didScheduleSystemAlarm: false,
                didApply: false,
                isStale: true
            )
        }

        storeWakeTime(weekday: weekday, hour: hour, minute: minute)
        scheduledWeekdays.insert(weekday)
        markMutation(for: weekday, timestamp: createdAtInterval)
        lastScheduledSession = nextUpcomingSession

        SleepSessionManager.shared.log(
            "Watch UI: Updated weekly alarm for weekday \(weekday) to \(String(format: "%02d:%02d", hour, minute))"
        )

        let didSchedule = await scheduleSession(alarmID: alarmID, createdAt: createdAt)
        postExternalScheduleChange(weekday: weekday)

        return WatchWeeklyAlarmApplyResult(
            affectedAlarm: alarmSnapshot(for: weekday),
            nextAlarm: nextUpcomingAlarm,
            didScheduleSystemAlarm: didSchedule,
            didApply: true,
            isStale: false
        )
    }

    func moveWeeklyAlarm(weekday: Int, offsetMinutes: Int, forward: Bool) async throws -> WeeklyAlarmOperationResult {
        guard (1...7).contains(weekday) else { throw WeeklyAlarmError.invalidWeekday }
        guard scheduledWeekdays.contains(weekday) else { throw WeeklyAlarmError.inactiveWeekday }
        guard offsetMinutes > 0 else { throw WeeklyAlarmError.invalidOffset }

        let currentSeconds = Int((wakeTimes[String(weekday)] ?? TimeInterval(7 * 3600)).rounded())
        let signedOffset = (forward ? offsetMinutes : -offsetMinutes) * 60
        let newSeconds = currentSeconds + signedOffset

        guard (0..<24 * 3600).contains(newSeconds) else {
            throw WeeklyAlarmError.crossesDayBoundary
        }

        let hour = newSeconds / 3600
        let minute = (newSeconds % 3600) / 60
        SleepSessionManager.shared.log("Siri: Move weekly alarm for weekday \(weekday) by \(signedOffset / 60)m")
        return try await setWeeklyAlarm(weekday: weekday, hour: hour, minute: minute)
    }

    func cancelWeeklyAlarm(weekday: Int) async throws -> WeeklyAlarmOperationResult {
        guard (1...7).contains(weekday) else { throw WeeklyAlarmError.invalidWeekday }
        guard scheduledWeekdays.contains(weekday) else { throw WeeklyAlarmError.inactiveWeekday }

        let previousAlarm = alarmSnapshot(for: weekday)
        scheduledWeekdays.remove(weekday)
        markMutation(for: weekday)
        lastScheduledSession = nextUpcomingSession

        SleepSessionManager.shared.log("Siri: Cancel weekly alarm for weekday \(weekday)")

        let didSchedule = await scheduleSession()
        return WeeklyAlarmOperationResult(
            affectedAlarm: previousAlarm,
            nextAlarm: nextUpcomingAlarm,
            didScheduleSystemAlarm: didSchedule
        )
    }

    func clearCurrentSelection() {
        lastScheduledSession = nextUpcomingSession
    }

    func mutationTime(for weekday: Int) -> TimeInterval {
        weekdayMutationTimes[String(weekday)] ?? 0
    }

    func markMutation(for weekday: Int, at date: Date = Date()) {
        markMutation(for: weekday, timestamp: date.timeIntervalSince1970)
    }

    func markMutation(for weekday: Int, timestamp: TimeInterval) {
        weekdayMutationTimes[String(weekday)] = timestamp
    }

    func postExternalScheduleChange(weekday: Int) {
        NotificationCenter.default.post(
            name: Self.externalScheduleDidChangeNotification,
            object: self,
            userInfo: [Self.externalScheduleChangedWeekdayKey: weekday]
        )
    }


}
