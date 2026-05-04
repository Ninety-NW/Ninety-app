import AppIntents

struct NinetyWatchShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .navy }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WatchSetNinetyAlarmIntent(),
            phrases: [
                "Svegliami con \(.applicationName) \(\.$weekday)",
                "Wake me up with \(.applicationName) on \(\.$weekday)",
                "Imposta la sveglia \(.applicationName)",
                "Set the \(.applicationName) alarm"
            ],
            shortTitle: "Imposta Sveglia",
            systemImageName: "alarm"
        )

        AppShortcut(
            intent: WatchGetNinetyAlarmIntent(),
            phrases: [
                "A che ora è la sveglia di \(.applicationName)",
                "Dimmi la prossima sveglia \(.applicationName)",
                "A che ora è la sveglia \(.applicationName) di \(\.$weekday)",
                "What time is the \(.applicationName) alarm",
                "What time is the \(.applicationName) alarm on \(\.$weekday)"
            ],
            shortTitle: "Controlla Sveglia",
            systemImageName: "clock"
        )

        AppShortcut(
            intent: WatchUpdateNinetyAlarmIntent(),
            phrases: [
                "Sposta la sveglia \(.applicationName) di \(\.$weekday)",
                "Move the \(.applicationName) alarm on \(\.$weekday)",
                "Sposta la sveglia \(.applicationName)",
                "Move the \(.applicationName) alarm"
            ],
            shortTitle: "Sposta Sveglia",
            systemImageName: "arrow.forward.circle"
        )

        AppShortcut(
            intent: WatchCancelNinetyAlarmIntent(),
            phrases: [
                "Annulla la sveglia \(.applicationName) di \(\.$weekday)",
                "Disattiva la sveglia \(.applicationName) di \(\.$weekday)",
                "Cancel the \(.applicationName) alarm on \(\.$weekday)"
            ],
            shortTitle: "Annulla Sveglia",
            systemImageName: "xmark.circle"
        )
    }
}
