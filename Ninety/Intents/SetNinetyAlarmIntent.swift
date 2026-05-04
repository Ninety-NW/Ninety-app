import AppIntents
import Foundation

struct SetNinetyAlarmIntent: AppIntent {
    static let title: LocalizedStringResource = "Imposta Sveglia Ninety"
    static let description = IntentDescription("Imposta una sveglia Ninety per un giorno della settimana e un orario specifici.")
    static let openAppWhenRun = false

    @Parameter(
        title: "Giorno",
        description: "Il giorno della settimana da attivare.",
        requestValueDialog: IntentDialog("Per quale giorno vuoi impostare la sveglia Ninety?")
    )
    var weekday: NinetyWeekday

    @Parameter(
        title: "Orario",
        description: "L'orario massimo entro cui vuoi essere svegliato.",
        kind: .time,
        requestValueDialog: IntentDialog("A che ora vuoi svegliarti?")
    )
    var wakeTime: Date

    static var parameterSummary: some ParameterSummary {
        Summary("Svegliami con Ninety \(\.$weekday) alle \(\.$wakeTime)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = await NinetyAlarmIntentService.setAlarm(
            weekday: weekday,
            wakeTime: wakeTime
        )
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}
