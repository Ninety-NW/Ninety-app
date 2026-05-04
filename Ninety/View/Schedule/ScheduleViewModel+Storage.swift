import Foundation
import SwiftUI

extension ScheduleViewModel {
    func observeExternalScheduleChanges() {
        let weekdayKey = Self.externalScheduleChangedWeekdayKey
        externalScheduleObserver = NotificationCenter.default.addObserver(
            forName: Self.externalScheduleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let changedWeekday = notification.userInfo?[weekdayKey] as? Int
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reloadScheduleFromStorage(changedWeekday: changedWeekday)
            }
        }
    }

    func reloadScheduleFromStorage(changedWeekday: Int?) {
        wakeTimes = Self.loadWakeTimesFromStorage()
        scheduledWeekdays = Self.loadScheduledWeekdaysFromStorage()
        weekdayMutationTimes = Self.loadWeekdayMutationTimesFromStorage()
        updateCurrentWakeUpTime()
        lastScheduledSession = nextUpcomingSession

        if let changedWeekday {
            logClock("External schedule change reloaded for weekday \(changedWeekday).")
        } else {
            logClock("External schedule change reloaded.")
        }
    }

    static func loadWakeTimesFromStorage() -> [String: TimeInterval] {
        let storedWakeTimes = UserDefaults.standard.dictionary(forKey: StorageKey.wakeTimesDict) as? [String: TimeInterval] ?? [:]

        // Backward compatibility: migrate old single time stored as timeIntervalSince1970
        var initialWakeTimes = storedWakeTimes
        if initialWakeTimes.isEmpty {
            if let oldStored = UserDefaults.standard.object(forKey: StorageKey.wakeTime) as? TimeInterval {
                // Convert legacy timeIntervalSince1970 to seconds-since-midnight
                let legacyDate = Date(timeIntervalSince1970: oldStored)
                let cal = Calendar.current
                let h = cal.component(.hour, from: legacyDate)
                let m = cal.component(.minute, from: legacyDate)
                let midnightOffset = TimeInterval(h * 3600 + m * 60)
                for i in 1...7 { initialWakeTimes[String(i)] = midnightOffset }
            }
        } else {
            // One-time migration: convert any legacy timestamps to seconds-since-midnight.
            // Legacy timestamps are either very large (> 86400) or negative.
            var migrated = false
            let migrationCal = Calendar(identifier: .gregorian)
            for (key, value) in initialWakeTimes {
                if value > 86400 || value < 0 {
                    let legacyDate = Date(timeIntervalSince1970: value)
                    let h = migrationCal.component(.hour, from: legacyDate)
                    let m = migrationCal.component(.minute, from: legacyDate)
                    // Ensure we don't carry over corrupted sub-minute precision
                    initialWakeTimes[key] = TimeInterval(h * 3600 + m * 60)
                    migrated = true
                }
            }
            if migrated {
                UserDefaults.standard.set(initialWakeTimes, forKey: StorageKey.wakeTimesDict)
            }
        }

        return initialWakeTimes
    }

    static func loadScheduledWeekdaysFromStorage() -> Set<Int> {
        Set(UserDefaults.standard.array(forKey: StorageKey.scheduledWeekdays) as? [Int] ?? [])
    }

    static func loadWeekdayMutationTimesFromStorage() -> [String: TimeInterval] {
        guard let dictionary = UserDefaults.standard.dictionary(forKey: StorageKey.weekdayMutationTimes) else {
            return [:]
        }
        return dictionary.compactMapValues { value in
            if let timeInterval = value as? TimeInterval {
                return timeInterval
            }
            if let number = value as? NSNumber {
                return number.doubleValue
            }
            if let string = value as? String {
                return TimeInterval(string)
            }
            return nil
        }
    }

    func alarmSnapshot(for weekday: Int) -> WeeklyAlarmSnapshot? {
        guard scheduledWeekdays.contains(weekday),
              let (hour, minute) = wakeTimeComponents(for: weekday),
              let wakeUpDate = nextWakeUpDate(for: weekday, hour: hour, minute: minute)
        else {
            return nil
        }

        return WeeklyAlarmSnapshot(
            weekday: weekday,
            hour: hour,
            minute: minute,
            wakeUpDate: wakeUpDate
        )
    }

    func userFriendlyWatchStatus(from status: String) -> String {
        let preferredLang = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        if status.contains("No watch session activity") {
            return "Not started yet".localized(for: preferredLang)
        }
        if status.localizedCaseInsensitiveContains("Open Ninety on Apple Watch to arm Smart Alarm") ||
            status.localizedCaseInsensitiveContains("Queued")
        {
            return "Open the Watch app to finish setting up".localized(for: preferredLang)
        }
        if status.localizedCaseInsensitiveContains("armed") {
            return "Scheduled".localized(for: preferredLang)
        }
        if status.localizedCaseInsensitiveContains("Session Started") ||
            status.localizedCaseInsensitiveContains("Recording") ||
            status.localizedCaseInsensitiveContains("Delivering backlog")
        {
            return "Tracking in progress".localized(for: preferredLang)
        }
        if status.localizedCaseInsensitiveContains("Monitoring Paused") {
            return "Wake-up delivered".localized(for: preferredLang)
        }
        return status
    }

    func userFriendlyAlarmStatus(from status: String) -> String {
        let preferredLang = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        if status == "No alarms configured." {
            return "No alarms configured.".localized(for: preferredLang)
        }
        if status.localizedCaseInsensitiveContains("Authorized") {
            return "Ready".localized(for: preferredLang)
        }
        if status.localizedCaseInsensitiveContains("AlarmKit fallback set") ||
            status.localizedCaseInsensitiveContains("AlarmKit alarm set") ||
            status.localizedCaseInsensitiveContains("Alarm set") {
            return "Scheduled".localized(for: preferredLang)
        }
        if status.localizedCaseInsensitiveContains("Smart wake triggered on Watch") {
            return "Wake-up triggered".localized(for: preferredLang)
        }
        if status.localizedCaseInsensitiveContains("Alarm active") ||
            status.localizedCaseInsensitiveContains("DYNAMIC WAKE EVENT") ||
            status.localizedCaseInsensitiveContains("Executed") {
            return "Wake-up triggered".localized(for: preferredLang)
        }
        if status.localizedCaseInsensitiveContains("Alarm alerting") {
            return "Wake-up delivered".localized(for: preferredLang)
        }
        return status
    }

    var nextUpcomingWakeUpDate: Date? {
        nextUpcomingAlarm?.wakeUpDate
    }

    var fallbackProjectedSession: SmartAlarmManager.ScheduledSleepSession {
        var wakeUpDate = currentWakeUpTime
        if wakeUpDate <= Date() {
            wakeUpDate = Calendar.current.date(byAdding: .day, value: 1, to: wakeUpDate) ?? wakeUpDate
        }
        return makeSession(for: wakeUpDate)
    }

    func makeSession(for wakeUpDate: Date) -> SmartAlarmManager.ScheduledSleepSession {
        SmartAlarmManager.ScheduledSleepSession(
            wakeUpDate: wakeUpDate,
            monitoringStartDate: wakeUpDate.addingTimeInterval(-SmartAlarmManager.monitoringLeadTime)
        )
    }

    func validate(weekday: Int, hour: Int, minute: Int) throws {
        guard (1...7).contains(weekday) else { throw WeeklyAlarmError.invalidWeekday }
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw WeeklyAlarmError.invalidTime
        }
    }

    func storeWakeTime(weekday: Int, hour: Int, minute: Int) {
        let key = String(weekday)
        wakeTimes[key] = TimeInterval(hour * 3600 + minute * 60).rounded()

        if selectedWeekday == weekday {
            selectedDayHour = hour
            selectedDayMinute = minute
            currentWakeUpTime = Self.todayDate(hour: hour, minute: minute)
        }
    }

    func wakeTimeComponents(for weekday: Int) -> (hour: Int, minute: Int)? {
        guard (1...7).contains(weekday) else { return nil }

        let totalSeconds = Int((wakeTimes[String(weekday)] ?? TimeInterval(7 * 3600)).rounded())
        return (totalSeconds / 3600, (totalSeconds % 3600) / 60)
    }

    func nextWakeUpDate(for weekday: Int, hour: Int, minute: Int) -> Date? {
        let calendar = Calendar.current
        let now = Date()

        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        components.weekday = weekday
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard var candidateDate = calendar.date(from: components) else {
            return nil
        }

        if candidateDate <= now {
            candidateDate = calendar.date(byAdding: .day, value: 7, to: candidateDate) ?? candidateDate
        }

        return candidateDate
    }

    func requestAlarmPermissions() async -> Bool {
        await withCheckedContinuation { continuation in
            SmartAlarmManager.shared.requestPermissions { granted in
                continuation.resume(returning: granted)
            }
        }
    }

}
