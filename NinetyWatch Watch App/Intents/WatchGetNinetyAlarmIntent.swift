import AppIntents
import Foundation

struct WatchGetNinetyAlarmIntent: AppIntent {
    static let title: LocalizedStringResource = "Controlla Sveglia Ninety"
    static let description = IntentDescription("Chiedi a Siri dall'Apple Watch a che ora è la sveglia Ninety.")
    static let openAppWhenRun = false

    @Parameter(
        title: "Giorno",
        description: "Il giorno da controllare. Se non lo specifichi, Ninety userà la prossima sveglia attiva.",
        requestValueDialog: IntentDialog("Per quale giorno vuoi sapere l'orario?")
    )
    var weekday: WatchNinetyWeekday?

    static var parameterSummary: some ParameterSummary {
        Summary("Dimmi la sveglia Ninety")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            var params: [String: Any] = [:]
            if let weekday {
                params["weekday"] = weekday.calendarWeekday
            }

            let dialog = try await WatchIntentRelay.shared.relay(
                action: "getAlarm",
                params: params
            )
            return .result(dialog: IntentDialog(stringLiteral: dialog))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        }
    }
}
