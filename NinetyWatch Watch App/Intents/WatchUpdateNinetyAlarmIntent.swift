import AppIntents
import Foundation

enum WatchAlarmOffsetDirection: String, AppEnum {
    case forward
    case backward

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Direzione"

    static let caseDisplayRepresentations: [WatchAlarmOffsetDirection: DisplayRepresentation] = [
        .forward: DisplayRepresentation(title: "in avanti", synonyms: ["avanti", "forward", "later"]),
        .backward: DisplayRepresentation(title: "indietro", synonyms: ["backward", "earlier"])
    ]
}

struct WatchUpdateNinetyAlarmIntent: AppIntent {
    static let title: LocalizedStringResource = "Sposta Sveglia Ninety"
    static let description = IntentDescription("Sposta la sveglia Ninety dall'Apple Watch inoltrando il comando all'iPhone.")
    static let openAppWhenRun = false

    @Parameter(
        title: "Giorno",
        description: "Il giorno della sveglia da spostare.",
        requestValueDialog: IntentDialog("Quale giorno vuoi spostare?")
    )
    var weekday: WatchNinetyWeekday

    @Parameter(
        title: "Minuti",
        description: "Quanti minuti vuoi spostare la sveglia?",
        default: 60,
        requestValueDialog: IntentDialog("Di quanti minuti vuoi spostare la sveglia?")
    )
    var offsetMinutes: Int

    @Parameter(
        title: "Direzione",
        description: "Vuoi spostare la sveglia in avanti o indietro?",
        default: WatchAlarmOffsetDirection.forward,
        requestValueDialog: IntentDialog("Vuoi spostarla in avanti o indietro?")
    )
    var direction: WatchAlarmOffsetDirection

    static var parameterSummary: some ParameterSummary {
        Summary("Sposta la sveglia Ninety di \(\.$weekday) di \(\.$offsetMinutes) minuti")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let dialog = try await WatchIntentRelay.shared.relay(
                action: "updateAlarm",
                params: [
                    "weekday": weekday.calendarWeekday,
                    "offsetMinutes": offsetMinutes,
                    "direction": direction.rawValue
                ]
            )
            return .result(dialog: IntentDialog(stringLiteral: dialog))
        } catch {
            let errorMsg = "Non sono riuscito a comunicare con l'iPhone: \(error.localizedDescription)"
            return .result(dialog: IntentDialog(stringLiteral: errorMsg))
        }
    }
}
