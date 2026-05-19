//
//  SettingsViewModel.swift
//  Ninety
//
//  Created by Deimante Valunaite on 11/07/2024.
//

import SwiftUI
import UserNotifications

// MARK: - App Theme

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case night = "Night"
    
    var id: String { rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .night: return .dark
        }
    }
    
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .night: return "moon.stars.fill"
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case italian = "it"
    case chinese = "zh-Hans"
    case spanish = "es"
    case arabic = "ar"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .italian:
            return "Italiano"
        case .chinese:
            return "中文"
        case .spanish:
            return "Español"
        case .arabic:
            return "العربية"
        }
    }
}

extension String {
    func localized(for languageCode: String) -> String {
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(self, comment: "")
        }
        return bundle.localizedString(forKey: self, value: nil, table: nil)
    }
}

class SettingsViewModel: ObservableObject {
    @AppStorage("appTheme") var selectedTheme: AppTheme = .system
    
    // Smart Alarm configuration
    @AppStorage("smartWakeWindow") var smartWakeWindow: Int = 30 // minutes before alarm to start sensing
    @AppStorage("hapticAlarm") var hapticAlarm: Bool = true // vibrate gently before ringing
    @AppStorage("hapticFeedbackEnabled") var hapticFeedbackEnabled: Bool = true // UI haptic feedback
    @AppStorage("saveToHealthKit") var saveToHealthKit: Bool = true // save sleep data
    
    /// Guard flag to prevent re-entrant didSet → enableNotifications → didSet loop.
    private var isUpdatingNotifications = false
    
    @AppStorage("isNotificationsEnabled") var isNotificationsEnabled: Bool = false {
        didSet {
            guard !isUpdatingNotifications else { return }
            if isNotificationsEnabled {
                enableNotifications()
            }
        }
    }
    
    func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isUpdatingNotifications = true
                self.isNotificationsEnabled = (settings.authorizationStatus == .authorized)
                self.isUpdatingNotifications = false
            }
        }
    }
    
    private func enableNotifications() {
        isUpdatingNotifications = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { success, error in
            DispatchQueue.main.async {
                self.isNotificationsEnabled = success
                self.isUpdatingNotifications = false
            }
        }
    }
}
