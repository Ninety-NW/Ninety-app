//
//  ContentView.swift
//  NinetyWatch Watch App
//
//  Created by Cristian on 02/04/26.
//

import SwiftUI

enum WatchCopyKey {
    case appName
    case nextAlarm
    case tapToChange
    case noActiveAlarms
    case setOnIPhone
    case today
    case tomorrow
    case monitoring
    case scheduled
    case waiting
    case attention
    case openWatchToSet
    case synced
    case queued
    case watchOnly
    case setAlarm
    case save
    case saved
    case syncPending
    case phoneUnavailable
    case syncFailed
    case syncing

    var englishKey: String {
        switch self {
        case .appName: return "Ninety"
        case .nextAlarm: return "Next alarm"
        case .tapToChange: return "Tap to change"
        case .noActiveAlarms: return "No active alarms"
        case .setOnIPhone: return "Set your next alarm on iPhone"
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .monitoring: return "Monitoring active"
        case .scheduled: return "Alarm scheduled"
        case .waiting: return "Waiting for the next alarm"
        case .attention: return "Attention"
        case .openWatchToSet: return "Open the Watch app to set it"
        case .synced: return "Synced"
        case .queued: return "Connected"
        case .watchOnly: return "Watch only"
        case .setAlarm: return "Set Ninety Alarm"
        case .save: return "Save"
        case .saved: return "Saved"
        case .syncPending: return "Pending sync"
        case .phoneUnavailable: return "iPhone unavailable"
        case .syncFailed: return "Sync failed"
        case .syncing: return "Syncing"
        }
    }
}

struct WatchCopy {
    let localeIdentifier: String

    var normalizedIdentifier: String {
        localeIdentifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    var languageCode: String {
        if normalizedIdentifier.hasPrefix("zh-hans") { return "zh-Hans" }
        if normalizedIdentifier.hasPrefix("ar") { return "ar" }
        if normalizedIdentifier.hasPrefix("it") { return "it" }
        if normalizedIdentifier.hasPrefix("es") { return "es" }
        return "en"
    }

    func text(_ key: WatchCopyKey) -> String {
        let englishKey = key.englishKey
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(englishKey, comment: "")
        }
        return bundle.localizedString(forKey: englishKey, value: nil, table: nil)
    }
}

enum WatchTimeField: Hashable {
    case hour, minute
}

