import AppIntents
import Foundation

struct WatchSetNinetyAlarmIntent: AppIntent {
    static let title: LocalizedStringResource = "Imposta Sveglia Ninety"
    static let description = IntentDescription("Imposta la sveglia Ninety dall'Apple Watch inoltrando il comando all'iPhone.")
    static let openAppWhenRun = false

    @Parameter(
        title: "Giorno",
        description: "Il giorno della settimana da attivare.",
        requestValueDialog: IntentDialog("Per quale giorno vuoi impostare la sveglia Ninety?")
    )
    var weekday: WatchNinetyWeekday

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

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let dialog = try await WatchIntentRelay.shared.relay(
                action: "setAlarm",
                params: [
                    "weekday": weekday.calendarWeekday,
                    "wakeTime": wakeTime.timeIntervalSince1970
                ]
            )
            return .result(dialog: IntentDialog(stringLiteral: dialog))
        } catch {
            let errorMsg = "Non sono riuscito a comunicare con l'iPhone: \(error.localizedDescription)"
            return .result(dialog: IntentDialog(stringLiteral: errorMsg))
        }
    }
}
