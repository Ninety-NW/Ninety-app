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
    @StateObject private var sleepSessionManager: SleepSessionManager
    @StateObject private var scheduleViewModel: ScheduleViewModel
    @StateObject private var tourFrameStore = TourFrameStore()
    
    init() {
        // Core initialization to bind WCSession & UNUserNotification delegates immediately on launch.
        let sleepManager = SleepSessionManager()
        self._sleepSessionManager = StateObject(wrappedValue: sleepManager)
        
        let scheduleVM = ScheduleViewModel(sleepManager: sleepManager)
        self._scheduleViewModel = StateObject(wrappedValue: scheduleVM)
        
        _ = SmartAlarmManager.shared
        SmartAlarmManager.shared.sleepSessionManager = sleepManager
        NinetyShortcutsProvider.updateAppShortcutParameters()
    }
    
    var body: some Scene {
        WindowGroup {
            OnboardingView()
                .preferredColorScheme(selectedTheme.colorScheme)
                .environmentObject(sleepSessionManager)
                .environmentObject(scheduleViewModel)
                .environmentObject(tourFrameStore)
        }
    }
}
