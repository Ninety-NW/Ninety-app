import Foundation
import UserNotifications

enum WatchWakeNotificationConstants {
    nonisolated static let finalWakeIdentifier = "it.ninety.watch.final-wake"
    nonisolated static let smartWakeIdentifier = "it.ninety.watch.smart-wake"
    nonisolated static let categoryIdentifier = "it.ninety.watch.wake"
}

@MainActor
final class WatchWakeNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WatchWakeNotificationDelegate()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let identifier = notification.request.identifier
        if identifier == WatchWakeNotificationConstants.finalWakeIdentifier ||
            identifier == WatchWakeNotificationConstants.smartWakeIdentifier {
            Task { @MainActor in
                WatchSensorManager.shared.handleWakeNotification(identifier: identifier)
            }
        }
        completionHandler([.sound, .banner])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        if identifier == WatchWakeNotificationConstants.finalWakeIdentifier ||
            identifier == WatchWakeNotificationConstants.smartWakeIdentifier {
            Task { @MainActor in
                WatchSensorManager.shared.handleWakeNotification(identifier: identifier)
            }
        }
        completionHandler()
    }
}

final class WatchWakeNotificationScheduler {
    static let shared = WatchWakeNotificationScheduler()

    private init() {}

    func configure() {
        let center = UNUserNotificationCenter.current()
        Task { @MainActor in
            center.delegate = WatchWakeNotificationDelegate.shared
        }
        requestAuthorizationIfNeeded()
    }

    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func scheduleFinalWakeNotification(at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Sveglia"
        content.body = "E ora di svegliarti."
        content.sound = .default
        content.categoryIdentifier = WatchWakeNotificationConstants.categoryIdentifier

        let components = Calendar.current.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: WatchWakeNotificationConstants.finalWakeIdentifier,
            content: content,
            trigger: trigger
        )

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [WatchWakeNotificationConstants.finalWakeIdentifier])
        center.add(request)
    }

    func sendImmediateWakeNotification(reason: String) {
        let content = UNMutableNotificationContent()
        content.title = "Sveglia"
        content.body = reason
        content.sound = .default
        content.categoryIdentifier = WatchWakeNotificationConstants.categoryIdentifier

        let request = UNNotificationRequest(
            identifier: WatchWakeNotificationConstants.smartWakeIdentifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func cancelWakeNotifications() {
        let identifiers = [
            WatchWakeNotificationConstants.finalWakeIdentifier,
            WatchWakeNotificationConstants.smartWakeIdentifier
        ]
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func cancelFinalWakeNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [WatchWakeNotificationConstants.finalWakeIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [WatchWakeNotificationConstants.finalWakeIdentifier])
    }
}

extension WatchSensorManager {
    func handleWakeNotification(identifier: String) {
        guard identifier == WatchWakeNotificationConstants.finalWakeIdentifier ||
            identifier == WatchWakeNotificationConstants.smartWakeIdentifier else {
            return
        }

        startWatchHapticWakePhase()
    }
}
