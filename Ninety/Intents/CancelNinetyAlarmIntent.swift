import AppIntents
import Foundation

struct CancelNinetyAlarmIntent: AppIntent {
    static let title: LocalizedStringResource = "Annulla Sveglia Ninety"
    static let description = IntentDescription("Disattiva la sveglia Ninety per un giorno della settimana.")
    static let openAppWhenRun = false

    @Parameter(
        title: "Giorno",
        description: "Il giorno della sveglia da annullare.",
        requestValueDialog: IntentDialog("Per quale giorno vuoi annullare la sveglia Ninety?")
    )
    var weekday: NinetyWeekday

    static var parameterSummary: some ParameterSummary {
        Summary("Annulla la sveglia Ninety di \(\.$weekday)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = await NinetyAlarmIntentService.cancelAlarm(weekday: weekday)
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

struct StopNinetyWakeAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Ferma Sveglia Ninety"
    static let description = IntentDescription("Ferma la sveglia Ninety attiva su iPhone e Apple Watch.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await SmartAlarmManager.shared.cancelSessionNow()
        return .result()
    }
}
