import AppIntents
import Foundation

struct WatchCancelNinetyAlarmIntent: AppIntent {
    static let title: LocalizedStringResource = "Annulla Sveglia Ninety"
    static let description = IntentDescription("Annulla una sveglia Ninety settimanale dall'Apple Watch inoltrando il comando all'iPhone.")
    static let openAppWhenRun = false

    @Parameter(
        title: "Giorno",
        description: "Il giorno della sveglia da annullare.",
        requestValueDialog: IntentDialog("Per quale giorno vuoi annullare la sveglia Ninety?")
    )
    var weekday: WatchNinetyWeekday

    static var parameterSummary: some ParameterSummary {
        Summary("Annulla la sveglia Ninety di \(\.$weekday)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let dialog = try await WatchIntentRelay.shared.relay(
                action: "cancelAlarm",
                params: ["weekday": weekday.calendarWeekday]
            )
            return .result(dialog: IntentDialog(stringLiteral: dialog))
        } catch {
            let errorMsg = "Non sono riuscito a comunicare con l'iPhone: \(error.localizedDescription)"
            return .result(dialog: IntentDialog(stringLiteral: errorMsg))
        }
    }
}
