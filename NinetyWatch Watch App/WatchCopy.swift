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
        switch languageCode {
        case "it":
            switch key {
            case .appName: return "Ninety"
            case .nextAlarm: return "Prossima sveglia"
            case .tapToChange: return "Tocca per modificare"
            case .noActiveAlarms: return "Nessuna sveglia attiva"
            case .setOnIPhone: return "Imposta la prossima su iPhone"
            case .today: return "Oggi"
            case .tomorrow: return "Domani"
            case .monitoring: return "Monitoraggio attivo"
            case .scheduled: return "Sveglia programmata"
            case .waiting: return "In attesa della prossima sveglia"
            case .attention: return "Attenzione"
            case .openWatchToSet: return "Apri l'app su Watch per impostarla"
            case .synced: return "Sincronizzato"
            case .queued: return "Connesso"
            case .watchOnly: return "Solo Watch"
            case .setAlarm: return "Set Ninety Alarm"
            case .save: return "Salva"
            case .saved: return "Salvato"
            case .syncPending: return "Da sincronizzare"
            case .phoneUnavailable: return "iPhone non raggiungibile"
            case .syncFailed: return "Sync non riuscito"
            case .syncing: return "Sincronizzo"
            }
        case "es":
            switch key {
            case .appName: return "Ninety"
            case .nextAlarm: return "Próxima alarma"
            case .tapToChange: return "Toca para cambiar"
            case .noActiveAlarms: return "No hay alarmas activas"
            case .setOnIPhone: return "Configura la próxima en iPhone"
            case .today: return "Hoy"
            case .tomorrow: return "Mañana"
            case .monitoring: return "Seguimiento activo"
            case .scheduled: return "Alarma programada"
            case .waiting: return "Esperando la próxima alarma"
            case .attention: return "Atención"
            case .openWatchToSet: return "Abre la app en el Watch para configurarla"
            case .synced: return "Sincronizado"
            case .queued: return "Conectado"
            case .watchOnly: return "Solo Watch"
            case .setAlarm: return "Set Ninety Alarm"
            case .save: return "Guardar"
            case .saved: return "Guardado"
            case .syncPending: return "Por sincronizar"
            case .phoneUnavailable: return "iPhone no disponible"
            case .syncFailed: return "Sincronización fallida"
            case .syncing: return "Sincronizando"
            }
        case "zh-Hans":
            switch key {
            case .appName: return "Ninety"
            case .nextAlarm: return "下一个闹钟"
            case .tapToChange: return "点按修改"
            case .noActiveAlarms: return "没有已激活的闹钟"
            case .setOnIPhone: return "请在 iPhone 上设置下一次闹钟"
            case .today: return "今天"
            case .tomorrow: return "明天"
            case .monitoring: return "监测中"
            case .scheduled: return "闹钟已安排"
            case .waiting: return "等待下一次闹钟"
            case .attention: return "注意"
            case .openWatchToSet: return "打开 Watch App 以设置"
            case .synced: return "已同步"
            case .queued: return "已连接"
            case .watchOnly: return "仅 Watch"
            case .setAlarm: return "Set Ninety Alarm"
            case .save: return "保存"
            case .saved: return "已保存"
            case .syncPending: return "待同步"
            case .phoneUnavailable: return "iPhone 不可用"
            case .syncFailed: return "同步失败"
            case .syncing: return "正在同步"
            }
        case "ar":
            switch key {
            case .appName: return "Ninety"
            case .nextAlarm: return "المنبه التالي"
            case .tapToChange: return "اضغط للتعديل"
            case .noActiveAlarms: return "لا توجد منبهات نشطة"
            case .setOnIPhone: return "اضبط المنبه التالي على iPhone"
            case .today: return "اليوم"
            case .tomorrow: return "غدًا"
            case .monitoring: return "المراقبة نشطة"
            case .scheduled: return "المنبه مجدول"
            case .waiting: return "بانتظار المنبه التالي"
            case .attention: return "تنبيه"
            case .openWatchToSet: return "افتح التطبيق على الساعة لضبطه"
            case .synced: return "تمت المزامنة"
            case .queued: return "متصل"
            case .watchOnly: return "الساعة فقط"
            case .setAlarm: return "Set Ninety Alarm"
            case .save: return "حفظ"
            case .saved: return "تم الحفظ"
            case .syncPending: return "بانتظار المزامنة"
            case .phoneUnavailable: return "iPhone غير متاح"
            case .syncFailed: return "فشلت المزامنة"
            case .syncing: return "تتم المزامنة"
            }
        default:
            switch key {
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
}

enum WatchTimeField: Hashable {
    case hour, minute
}

