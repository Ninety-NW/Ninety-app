import AppIntents
import Foundation

struct GetNinetyAlarmIntent: AppIntent {
    static let title: LocalizedStringResource = "Controlla Sveglia Ninety"
    static let description = IntentDescription("Controlla la prossima sveglia Ninety o quella di un giorno specifico.")
    static let openAppWhenRun = false

    @Parameter(
        title: "Giorno",
        description: "Il giorno da controllare. Se non lo specifichi, Ninety userà la prossima sveglia attiva.",
        requestValueDialog: IntentDialog("Per quale giorno vuoi sapere l'orario?")
    )
    var weekday: NinetyWeekday?

    static var parameterSummary: some ParameterSummary {
        Summary("Dimmi la sveglia Ninety")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = NinetyAlarmIntentService.getAlarm(weekday: weekday)
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}
