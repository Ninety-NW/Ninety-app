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
        guard let language = AppLanguage(rawValue: languageCode) else {
            return self
        }

        switch language {
        case .english:
            return self
        case .italian:
            return italianTranslation ?? self
        case .chinese:
            return chineseTranslation ?? self
        case .spanish:
            return spanishTranslation ?? self
        case .arabic:
            return arabicTranslation ?? self
        }
    }

    private var italianTranslation: String? {
        switch self {
        case "Welcome to Ninety": return "Benvenuto in Ninety"
        case "Set Your Wake Time": return "Imposta il tuo orario"
        case "Track your sleep pattern and wake up refreshed.": return "Monitora il tuo sonno e svegliati riposato."
        case "Ninety uses on-device machine learning to find the ideal moment to wake you — within the time you set.":
            return "Ninety usa il machine learning on-device per trovare il momento ideale in cui svegliarti, entro l'orario che hai impostato."
        case "Tap the clock to choose when you need to be up. Ninety wakes you at the best point in your sleep cycle.":
            return "Tocca l'orologio per scegliere entro quando vuoi essere svegliato. Ninety ti sveglierà nel momento ideale del tuo ciclo di sonno."
        case "Each day can have its own wake-up time. Tap a day to select it and adjust the schedule.":
            return "Ogni giorno può avere un orario diverso. Tocca un giorno per selezionarlo e impostare la sua sveglia."
        case "Toggle the alarm for each day independently — keep your weekdays and weekends perfectly balanced.":
            return "Accendi o spegni la sveglia per ogni singolo giorno in modo indipendente."
        case "Your sleep data never leaves your device. No servers, no cloud — everything runs locally on your iPhone.":
            return "I tuoi dati sul sonno non lasciano mai il dispositivo. Niente server, niente cloud: tutto gira localmente sul tuo iPhone."
        case "Everything is set up. Sweet dreams.":
            return "È tutto pronto. Sogni d'oro."
        case "Get Started": return "Inizia"
        case "Replay Tour": return "Ripeti il tour"
        case "Opens the main sleep schedule": return "Apre la schermata principale della sveglia"
        case "By continuing, you agree to Ninety's \n**Terms of Service** and **Privacy Policy.**":
            return "Continuando, accetti i **Termini di servizio** e la **Privacy Policy** di Ninety."
        case "Ninety logo": return "Logo di Ninety"
        case "Wake up by": return "Sveglia entro"
        case "Next Up": return "Prossima sveglia"
        case "Select": return "Seleziona"
        case "Alarm On": return "Sveglia attiva"
        case "Alarm Off": return "Sveglia disattivata"
        case "Settings": return "Impostazioni"
        case "Diagnostics": return "Diagnostica"
        case "Done": return "Chiudi"
        case "Set Wake Time": return "Imposta orario"
        case "SMART ALARM": return "SVEGLIA INTELLIGENTE"
        case "Wake Window": return "Finestra di sveglia"
        case "Haptic Pre-Alarm": return "Pre-sveglia aptica"
        case "APPEARANCE": return "ASPETTO"
        case "Automatic": return "Automatico"
        case "PERMISSIONS": return "PERMESSI"
        case "Notifications": return "Notifiche"
        case "Apple Health": return "Apple Health"
        case "GENERAL": return "GENERALE"
        case "Language": return "Lingua"
        case "About Ninety": return "Informazioni su Ninety"
        case "Version": return "Versione"
        case "Smart sleep tracking powered by on-device ML. Your data stays on your devices.":
            return "Monitoraggio del sonno intelligente con ML on-device. I tuoi dati restano sui tuoi dispositivi."
        case "Haptic Feedback": return "Feedback aptico"
        case "Light": return "Chiaro"
        case "Night": return "Notte"
        case "System": return "Sistema"
        case "Next": return "Avanti"
        case "Customize Every Day": return "Personalizza ogni giorno"
        case "On or Off. Your Call.": return "Attiva o disattiva"
        case "Private by Design": return "Privacy integrata"
        case "You're All Set": return "È tutto pronto"
        case "Sound": return "Suono"
        case "Default": return "Predefinito"
        case "Chimes": return "Rintocchi"
        case "Anticipate": return "Anticipazione"
        case "Bloom": return "Fioritura"
        case "Calypso": return "Calypso"
        case "Fanfare": return "Fanfara"
        case "Noir": return "Noir"
        case "Tiptoe": return "Punta di piedi"
        default: return nil
        }
    }

    private var chineseTranslation: String? {
        switch self {
        case "Set Your Wake Time": return "设置唤醒时间"
        case "Track your sleep pattern and wake up refreshed.": return "追踪你的睡眠规律，醒来更精神。"
        case "Ninety uses on-device machine learning to find the ideal moment to wake you — within the time you set.":
            return "Ninety 使用端侧机器学习，在你设定的时间范围内找到最适合叫醒你的时刻。"
        case "Tap the clock to choose when you need to be up. Ninety wakes you at the best point in your sleep cycle.":
            return "点击时钟选择你最晚需要起床的时间。Ninety 会在你睡眠周期中最合适的时刻叫醒你。"
        case "Each day can have its own wake-up time. Tap a day to select it and adjust the schedule.":
            return "每天都可以有不同的起床时间。点击某一天即可选择并调整计划。"
        case "Toggle the alarm for each day independently — keep your weekdays and weekends perfectly balanced.":
            return "为每一天单独开关闹钟，让工作日和周末安排更灵活。"
        case "Your sleep data never leaves your device. No servers, no cloud — everything runs locally on your iPhone.":
            return "你的睡眠数据绝不会离开设备。没有服务器，没有云端，一切都在你的 iPhone 本地运行。"
        case "Everything is set up. Sweet dreams.":
            return "一切都已设置完成。祝你好梦。"
        case "Get Started": return "开始使用"
        case "Replay Tour": return "重新播放引导"
        case "Opens the main sleep schedule": return "打开主要睡眠计划界面"
        case "By continuing, you agree to Ninety's \n**Terms of Service** and **Privacy Policy.**":
            return "继续即表示你同意 Ninety 的**服务条款**和**隐私政策**。"
        case "Ninety logo": return "Ninety 标志"
        case "Wake up by": return "最晚唤醒时间"
        case "Next Up": return "下一次"
        case "Select": return "选择"
        case "Alarm On": return "闹钟已开启"
        case "Alarm Off": return "闹钟已关闭"
        case "Settings": return "设置"
        case "Diagnostics": return "诊断"
        case "Done": return "完成"
        case "Set Wake Time": return "设置起床时间"
        case "SMART ALARM": return "智能闹钟"
        case "Wake Window": return "唤醒窗口"
        case "Haptic Pre-Alarm": return "触觉预闹钟"
        case "APPEARANCE": return "外观"
        case "Automatic": return "自动"
        case "PERMISSIONS": return "权限"
        case "Notifications": return "通知"
        case "Apple Health": return "Apple 健康"
        case "GENERAL": return "通用"
        case "Language": return "语言"
        case "About Ninety": return "关于 Ninety"
        case "Version": return "版本"
        case "Smart sleep tracking powered by on-device ML. Your data stays on your devices.":
            return "由端侧机器学习驱动的智能睡眠追踪。你的数据始终保留在你的设备上。"
        case "Haptic Feedback": return "触觉反馈"
        case "Light": return "浅色"
        case "Night": return "夜间"
        case "System": return "系统"
        case "Next": return "下一步"
        case "Customize Every Day": return "自定义每天"
        case "On or Off. Your Call.": return "开或关，由你决定"
        case "Private by Design": return "隐私优先"
        case "You're All Set": return "一切就绪"
        case "Sound": return "提示音"
        case "Default": return "默认"
        default: return nil
        }
    }

    private var spanishTranslation: String? {
        switch self {
        case "Set Your Wake Time": return "Configura tu hora"
        case "Track your sleep pattern and wake up refreshed.": return "Sigue tu patrón de sueño y despierta renovado."
        case "Ninety uses on-device machine learning to find the ideal moment to wake you — within the time you set.":
            return "Ninety usa aprendizaje automático en el dispositivo para encontrar el momento ideal para despertarte dentro del horario que estableces."
        case "Tap the clock to choose when you need to be up. Ninety wakes you at the best point in your sleep cycle.":
            return "Toca el reloj para elegir a qué hora necesitas estar despierto. Ninety te despertará en el mejor punto de tu ciclo de sueño."
        case "Each day can have its own wake-up time. Tap a day to select it and adjust the schedule.":
            return "Cada día puede tener su propia hora de despertar. Toca un día para seleccionarlo y ajustar el horario."
        case "Toggle the alarm for each day independently — keep your weekdays and weekends perfectly balanced.":
            return "Activa o desactiva la alarma de cada día por separado para equilibrar entre semana y fines de semana."
        case "Your sleep data never leaves your device. No servers, no cloud — everything runs locally on your iPhone.":
            return "Tus datos de sueño nunca salen de tu dispositivo. Sin servidores, sin nube: todo se ejecuta localmente en tu iPhone."
        case "Everything is set up. Sweet dreams.":
            return "Todo está listo. Dulces sueños."
        case "Get Started": return "Empezar"
        case "Replay Tour": return "Repetir tour"
        case "Opens the main sleep schedule": return "Abre la pantalla principal del horario de sueño"
        case "By continuing, you agree to Ninety's \n**Terms of Service** and **Privacy Policy.**":
            return "Al continuar, aceptas los **Términos de servicio** y la **Política de privacidad** de Ninety."
        case "Ninety logo": return "Logotipo de Ninety"
        case "Wake up by": return "Despertar antes de"
        case "Next Up": return "Siguiente"
        case "Select": return "Seleccionar"
        case "Alarm On": return "Alarma activada"
        case "Alarm Off": return "Alarma desactivada"
        case "Settings": return "Ajustes"
        case "Diagnostics": return "Diagnóstico"
        case "Done": return "Listo"
        case "Set Wake Time": return "Configurar hora"
        case "SMART ALARM": return "ALARMA INTELIGENTE"
        case "Wake Window": return "Ventana de despertar"
        case "Haptic Pre-Alarm": return "Prealarma háptica"
        case "APPEARANCE": return "APARIENCIA"
        case "Automatic": return "Automático"
        case "PERMISSIONS": return "PERMISOS"
        case "Notifications": return "Notificaciones"
        case "Apple Health": return "Apple Health"
        case "GENERAL": return "GENERAL"
        case "Language": return "Idioma"
        case "About Ninety": return "Acerca de Ninety"
        case "Version": return "Versión"
        case "Smart sleep tracking powered by on-device ML. Your data stays on your devices.":
            return "Seguimiento inteligente del sueño impulsado por ML en el dispositivo. Tus datos permanecen en tus dispositivos."
        case "Haptic Feedback": return "Retroalimentación háptica"
        case "Light": return "Claro"
        case "Night": return "Noche"
        case "System": return "Sistema"
        case "Next": return "Siguiente"
        case "Customize Every Day": return "Personaliza cada día"
        case "On or Off. Your Call.": return "Actívalo o desactívalo"
        case "Private by Design": return "Privacidad por diseño"
        case "You're All Set": return "Todo listo"
        case "Sound": return "Sonido"
        case "Default": return "Predeterminado"
        default: return nil
        }
    }

    private var arabicTranslation: String? {
        switch self {
        case "Set Your Wake Time": return "اضبط وقت الاستيقاظ"
        case "Track your sleep pattern and wake up refreshed.": return "تابع نمط نومك واستيقظ منتعشًا."
        case "Ninety uses on-device machine learning to find the ideal moment to wake you — within the time you set.":
            return "يستخدم Ninety التعلم الآلي على الجهاز للعثور على اللحظة المثالية لإيقاظك ضمن الوقت الذي تحدده."
        case "Tap the clock to choose when you need to be up. Ninety wakes you at the best point in your sleep cycle.":
            return "اضغط على الساعة لاختيار الوقت الذي تحتاج فيه إلى الاستيقاظ. سيوقظك Ninety في أفضل نقطة من دورة نومك."
        case "Each day can have its own wake-up time. Tap a day to select it and adjust the schedule.":
            return "يمكن أن يكون لكل يوم وقت استيقاظ مختلف. اضغط على يوم لاختياره وضبط الجدول."
        case "Toggle the alarm for each day independently — keep your weekdays and weekends perfectly balanced.":
            return "شغّل أو أوقف المنبه لكل يوم بشكل مستقل للحفاظ على توازن مثالي بين أيام الأسبوع وعطلة نهاية الأسبوع."
        case "Your sleep data never leaves your device. No servers, no cloud — everything runs locally on your iPhone.":
            return "بيانات نومك لا تغادر جهازك أبدًا. لا خوادم ولا سحابة، كل شيء يعمل محليًا على iPhone."
        case "Everything is set up. Sweet dreams.":
            return "تم إعداد كل شيء. أحلامًا سعيدة."
        case "Get Started": return "ابدأ"
        case "Replay Tour": return "إعادة الجولة"
        case "Opens the main sleep schedule": return "يفتح شاشة جدول النوم الرئيسية"
        case "By continuing, you agree to Ninety's \n**Terms of Service** and **Privacy Policy.**":
            return "بالمتابعة، فإنك توافق على **شروط الخدمة** و**سياسة الخصوصية** الخاصة بـ Ninety."
        case "Ninety logo": return "شعار Ninety"
        case "Wake up by": return "الاستيقاظ قبل"
        case "Next Up": return "التالي"
        case "Select": return "اختيار"
        case "Alarm On": return "المنبه مفعّل"
        case "Alarm Off": return "المنبه متوقف"
        case "Settings": return "الإعدادات"
        case "Diagnostics": return "التشخيص"
        case "Done": return "تم"
        case "Set Wake Time": return "ضبط وقت الاستيقاظ"
        case "SMART ALARM": return "المنبه الذكي"
        case "Wake Window": return "نافذة الاستيقاظ"
        case "Haptic Pre-Alarm": return "منبه لمسي مسبق"
        case "APPEARANCE": return "المظهر"
        case "Automatic": return "تلقائي"
        case "PERMISSIONS": return "الأذونات"
        case "Notifications": return "الإشعارات"
        case "Apple Health": return "صحّة Apple"
        case "GENERAL": return "عام"
        case "Language": return "اللغة"
        case "About Ninety": return "حول Ninety"
        case "Version": return "الإصدار"
        case "Smart sleep tracking powered by on-device ML. Your data stays on your devices.":
            return "تتبع ذكي للنوم مدعوم بالتعلم الآلي على الجهاز. تبقى بياناتك على أجهزتك."
        case "Haptic Feedback": return "ردود فعل لمسية"
        case "Light": return "فاتح"
        case "Night": return "ليلي"
        case "System": return "النظام"
        case "Next": return "التالي"
        case "Customize Every Day": return "خصّص كل يوم"
        case "On or Off. Your Call.": return "تشغيل أو إيقاف، القرار لك"
        case "Private by Design": return "الخصوصية في الأساس"
        case "You're All Set": return "كل شيء جاهز"
        case "Sound": return "الصوت"
        case "Default": return "افتراضي"
        default: return nil
        }
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
