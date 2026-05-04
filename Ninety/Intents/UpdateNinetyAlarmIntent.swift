import AppIntents
import Foundation

struct UpdateNinetyAlarmIntent: AppIntent {
    static let title: LocalizedStringResource = "Sposta Sveglia Ninety"
    static let description = IntentDescription("Sposta la sveglia Ninety di un giorno specifico senza creare duplicati.")
    static let openAppWhenRun = false

    @Parameter(
        title: "Giorno",
        description: "Il giorno della sveglia da spostare.",
        requestValueDialog: IntentDialog("Quale giorno vuoi spostare?")
    )
    var weekday: NinetyWeekday

    @Parameter(
        title: "Minuti",
        description: "Quanti minuti vuoi spostare la sveglia.",
        default: 60,
        requestValueDialog: IntentDialog("Di quanti minuti vuoi spostare la sveglia?")
    )
    var offsetMinutes: Int

    @Parameter(
        title: "Direzione",
        description: "Sposta la sveglia in avanti o indietro.",
        default: AlarmOffsetDirection.forward,
        requestValueDialog: IntentDialog("Vuoi spostarla in avanti o indietro?")
    )
    var direction: AlarmOffsetDirection

    static var parameterSummary: some ParameterSummary {
        Summary("Sposta la sveglia Ninety di \(\.$weekday) di \(\.$offsetMinutes) minuti")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = await NinetyAlarmIntentService.moveAlarm(
            weekday: weekday,
            offsetMinutes: offsetMinutes,
            direction: direction
        )
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}
