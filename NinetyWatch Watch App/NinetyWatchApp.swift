//
//  NinetyWatchApp.swift
//  NinetyWatch Watch App
//
//  Created by Cristian on 02/04/26.
//

import SwiftUI
import WatchKit

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        _ = WatchSensorManager.shared
    }

    func applicationDidBecomeActive() {
        WatchSensorManager.shared.refreshConnectionStatus()
        WatchSensorManager.shared.setPendingScheduleIfPossible()
        WatchSensorManager.shared.retryPendingPayloadDelivery()
    }

    func handle(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        WatchSensorManager.shared.resumeScheduledSession(extendedRuntimeSession)
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
                WatchSensorManager.shared.retryPendingPayloadDelivery()
                connectivityTask.setTaskCompletedWithSnapshot(false)
            case let applicationTask as WKApplicationRefreshBackgroundTask:
                WatchSensorManager.shared.retryPendingPayloadDelivery()
                applicationTask.setTaskCompletedWithSnapshot(false)
            case let snapshotTask as WKSnapshotRefreshBackgroundTask:
                snapshotTask.setTaskCompleted(
                    restoredDefaultState: true,
                    estimatedSnapshotExpiration: .distantFuture,
                    userInfo: nil
                )
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}

@main
struct NinetyWatch_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
