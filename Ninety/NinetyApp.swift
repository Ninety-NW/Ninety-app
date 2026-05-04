//
//  NinetyApp.swift
//  Ninety
//
//  Created by Deimante Valunaite on 07/07/2024.
//

import SwiftUI
import AppIntents

@main
struct NinetyApp: App {
    @AppStorage("appTheme") private var selectedTheme: AppTheme = .system
    @StateObject private var scheduleViewModel = ScheduleViewModel()
    @StateObject private var tourFrameStore = TourFrameStore()
    
    init() {
        // Core initialization to bind WCSession & UNUserNotification delegates immediately on launch.
        // If these are not instantly mapped, WCSession cannot wake the iOS app from suspended states!
        _ = SleepSessionManager.shared
        _ = SmartAlarmManager.shared
        NinetyShortcutsProvider.updateAppShortcutParameters()
    }
    
    var body: some Scene {
        WindowGroup {
            OnboardingView()
                .preferredColorScheme(selectedTheme.colorScheme)
                .environmentObject(scheduleViewModel)
                .environmentObject(tourFrameStore)
        }
    }
}
