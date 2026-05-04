import AppIntents
import Foundation

enum NinetyWeekday: String, CaseIterable, AppEnum {
    case sunday
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Giorno"

    static let caseDisplayRepresentations: [NinetyWeekday: DisplayRepresentation] = [
        .sunday: DisplayRepresentation(title: "domenica", synonyms: ["Sunday"]),
        .monday: DisplayRepresentation(title: "lunedì", synonyms: ["lunedi", "Monday"]),
        .tuesday: DisplayRepresentation(title: "martedì", synonyms: ["martedi", "Tuesday"]),
        .wednesday: DisplayRepresentation(title: "mercoledì", synonyms: ["mercoledi", "Wednesday"]),
        .thursday: DisplayRepresentation(title: "giovedì", synonyms: ["giovedi", "Thursday"]),
        .friday: DisplayRepresentation(title: "venerdì", synonyms: ["venerdi", "Friday"]),
        .saturday: DisplayRepresentation(title: "sabato", synonyms: ["Saturday"])
    ]

    var calendarWeekday: Int {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        }
    }

    init?(calendarWeekday: Int) {
        switch calendarWeekday {
        case 1: self = .sunday
        case 2: self = .monday
        case 3: self = .tuesday
        case 4: self = .wednesday
        case 5: self = .thursday
        case 6: self = .friday
        case 7: self = .saturday
        default: return nil
        }
    }
}

enum AlarmOffsetDirection: String, AppEnum {
    case forward
    case backward

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Direzione"

    static let caseDisplayRepresentations: [AlarmOffsetDirection: DisplayRepresentation] = [
        .forward: DisplayRepresentation(title: "in avanti", synonyms: ["avanti", "forward", "later"]),
        .backward: DisplayRepresentation(title: "indietro", synonyms: ["backward", "earlier"])
    ]

    var movesForward: Bool { self == .forward }
}

@MainActor
enum NinetyAlarmIntentService {
    enum RelayError: LocalizedError {
        case invalidPayload

        var errorDescription: String? {
            "Non ho capito i dati del comando Siri."
        }
    }

    static func setAlarm(weekday: NinetyWeekday, wakeTime: Date) async -> String {
        await setAlarm(weekday: weekday.calendarWeekday, wakeTime: wakeTime)
    }

    static func setAlarm(weekday: Int, wakeTime: Date) async -> String {
        do {
            let result = try await ScheduleViewModel().setWeeklyAlarm(
                weekday: weekday,
                wakeTime: wakeTime
            )

            guard let alarm = result.affectedAlarm else {
                return "Non sono riuscito a leggere la sveglia appena impostata."
            }

            let scheduleNote = result.didScheduleSystemAlarm ? "" : " L'ho salvata, ma devi autorizzare AlarmKit per attivarla."
            return "Perfetto. La sveglia Ninety di \(weekdayName(alarm.weekday)) è impostata alle \(timeLabel(alarm.wakeUpDate)).\(nextAlarmSentence(from: result.nextAlarm))\(scheduleNote)"
        } catch {
            return error.localizedDescription
        }
    }

    static func getAlarm(weekday: NinetyWeekday?) -> String {
        getAlarm(weekday: weekday?.calendarWeekday)
    }

    static func getAlarm(weekday: Int?) -> String {
        let viewModel = ScheduleViewModel()

        if let weekday {
            guard let alarm = viewModel.alarmSnapshot(for: weekday) else {
                return "Non hai nessuna sveglia Ninety attiva per \(weekdayName(weekday))."
            }

            return "La sveglia Ninety di \(weekdayName(alarm.weekday)) è impostata alle \(timeLabel(alarm.wakeUpDate)). La prossima occorrenza è \(dateLabel(alarm.wakeUpDate))."
        }

        guard let nextAlarm = viewModel.nextUpcomingAlarm else {
            return "Non hai nessuna sveglia Ninety attiva."
        }

        return "La prossima sveglia Ninety è \(weekdayName(nextAlarm.weekday)) alle \(timeLabel(nextAlarm.wakeUpDate)). Il monitoraggio inizierà alle \(timeLabel(nextAlarm.session.monitoringStartDate))."
    }

    static func moveAlarm(weekday: NinetyWeekday, offsetMinutes: Int, direction: AlarmOffsetDirection) async -> String {
        await moveAlarm(
            weekday: weekday.calendarWeekday,
            offsetMinutes: offsetMinutes,
            forward: direction.movesForward
        )
    }

    static func moveAlarm(weekday: Int, offsetMinutes: Int, forward: Bool) async -> String {
        do {
            let result = try await ScheduleViewModel().moveWeeklyAlarm(
                weekday: weekday,
                offsetMinutes: offsetMinutes,
                forward: forward
            )

            guard let alarm = result.affectedAlarm else {
                return "Non sono riuscito a leggere la sveglia aggiornata."
            }

            let directionLabel = forward ? "in avanti" : "indietro"
            return "Fatto. Ho spostato la sveglia Ninety di \(weekdayName(alarm.weekday)) di \(minuteLabel(offsetMinutes)) \(directionLabel). Il nuovo orario è \(timeLabel(alarm.wakeUpDate)).\(nextAlarmSentence(from: result.nextAlarm))"
        } catch {
            return error.localizedDescription
        }
    }

    static func cancelAlarm(weekday: NinetyWeekday) async -> String {
        await cancelAlarm(weekday: weekday.calendarWeekday)
    }

    static func cancelAlarm(weekday: Int) async -> String {
        do {
            let result = try await ScheduleViewModel().cancelWeeklyAlarm(weekday: weekday)
            let dayName = weekdayName(result.affectedAlarm?.weekday ?? weekday)

            if let nextAlarm = result.nextAlarm {
                return "Fatto. Ho annullato la sveglia Ninety di \(dayName). La prossima sveglia attiva è \(weekdayName(nextAlarm.weekday)) alle \(timeLabel(nextAlarm.wakeUpDate))."
            }

            return "Fatto. Ho annullato la sveglia Ninety di \(dayName). Non ci sono altre sveglie attive."
        } catch {
            return error.localizedDescription
        }
    }

    static func dialogForRelay(action: String, payload: [String: Any]) async throws -> String {
        switch action {
        case "setAlarm":
            guard let weekday = payload["weekday"] as? Int,
                  let wakeTime = payload["wakeTime"] as? TimeInterval else {
                throw RelayError.invalidPayload
            }

            return await setAlarm(
                weekday: weekday,
                wakeTime: Date(timeIntervalSince1970: wakeTime)
            )

        case "getAlarm":
            return getAlarm(weekday: payload["weekday"] as? Int)

        case "updateAlarm":
            guard let weekday = payload["weekday"] as? Int,
                  let offsetMinutes = payload["offsetMinutes"] as? Int else {
                throw RelayError.invalidPayload
            }

            let rawDirection = payload["direction"] as? String
            let forward = rawDirection != "backward" && rawDirection != "indietro"
            return await moveAlarm(
                weekday: weekday,
                offsetMinutes: offsetMinutes,
                forward: forward
            )

        case "cancelAlarm":
            guard let weekday = payload["weekday"] as? Int else {
                throw RelayError.invalidPayload
            }

            return await cancelAlarm(weekday: weekday)

        default:
            throw RelayError.invalidPayload
        }
    }

    private static func nextAlarmSentence(from alarm: ScheduleViewModel.WeeklyAlarmSnapshot?) -> String {
        guard let alarm else { return "" }
        return " La prossima sveglia attiva è \(weekdayName(alarm.weekday)) alle \(timeLabel(alarm.wakeUpDate))."
    }

    private static func weekdayName(_ weekday: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale

        guard (1...7).contains(weekday) else {
            return "quel giorno"
        }

        return calendar.weekdaySymbols[weekday - 1]
    }

    private static func timeLabel(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().locale(locale).hour().minute())
    }

    private static func dateLabel(_ date: Date) -> String {
        date.formatted(.dateTime.locale(locale).weekday(.wide).day().month().hour().minute())
    }

    private static func minuteLabel(_ minutes: Int) -> String {
        minutes == 60 ? "un'ora" : "\(minutes) minuti"
    }

    private static var locale: Locale {
        Locale(identifier: UserDefaults.standard.string(forKey: "appLanguage") ?? "it_IT")
    }
}
