import SwiftUI

struct ContentView: View {
    @StateObject var sensorManager = WatchSensorManager.shared
    @StateObject var hapticManager = HapticWakeUpManager.shared
    @State var isEditingTime = false

    var copy: WatchCopy {
        WatchCopy(localeIdentifier: Locale.autoupdatingCurrent.identifier)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WatchPageBackground()

                WatchAlarmSetupView(sensorManager: sensorManager, copy: copy, isEditingTime: $isEditingTime)
                
                if !isEditingTime {
                    VStack {
                        Spacer()
                        WatchStatusFooter(sensorManager: sensorManager)
                            .padding(.bottom, -2) // Subtle nudge to the absolute edge
                    }
                    .ignoresSafeArea(.all, edges: .bottom)
                }
                
                if hapticManager.isPlaying {
                    AlarmView()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(10)
                }
            }
            .containerBackground(.black.gradient, for: .navigation)
            .onAppear {
                sensorManager.refreshStoredAlarmStateIfNeeded()
                sensorManager.requestHealthPermissions { _ in }
            }
        }
    }
}

struct WatchStatusFooter: View {
    @ObservedObject var sensorManager: WatchSensorManager
    
    var isSynced: Bool {
        sensorManager.connectionStatus.contains("reachable") || sensorManager.connectionStatus.contains("enabled")
    }
    
    var statusText: String {
        if isSynced {
            return "Synced"
        } else if sensorManager.connectionStatus.contains("unavailable") {
            return "Phone Offline"
        } else {
            return "Connecting..."
        }
    }
    
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isSynced ? Color.green : Color.red)
                .frame(width: 6, height: 6)
                .shadow(color: (isSynced ? Color.green : Color.red).opacity(0.5), radius: 2)
            
            Text(statusText)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(.white.opacity(0.04))
        }
    }
}

struct WatchPageBackground: View {
    var body: some View {
        Color.black
            .ignoresSafeArea()
    }
}

// MARK: - Alarm Setup

struct WatchAlarmSetupView: View {
    @ObservedObject var sensorManager: WatchSensorManager
    let copy: WatchCopy

    @State var wakeTime = WatchAlarmSetupView.defaultWakeTime()
    @State var internalHour = 7
    @State var internalMinute = 0
    @State var isApplyingSyncedAlarm = false
    @State var initialField: WatchTimeField = .hour
    @State var idleCrownValue: Double = 0
    @Binding var isEditingTime: Bool

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            if isEditingTime {
                TimeWheelField(hour: $internalHour, minute: $internalMinute, initialFocus: initialField)
                    .padding(.bottom, 4)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))

                HStack(spacing: 8) {
                    Button {
                        cancelEditing()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .background {
                        Circle()
                        .fill(.white.opacity(0.12))
                            .overlay {
                                Circle()
                                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
                            }
                    }
                    .foregroundStyle(.white.opacity(0.92))

                    Button {
                        updateWakeTimeFromInternal()
                        sensorManager.setNextAlarm(wakeTime: wakeTime)
                        withAnimation(.snappy(duration: 0.22)) {
                            isEditingTime = false
                        }
                    } label: {
                            HStack(spacing: 4) {
                                Image(systemName: buttonIconName)
                                Text(buttonTitle)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.blue) // Use a more consistent blue for the Watch
                    .disabled(sensorManager.weeklyAlarmSyncState == .saving)
                }
                .frame(maxWidth: .infinity)
                .transition(.opacity)
            } else {
                Button {
                    initialField = .hour
                    withAnimation(.snappy(duration: 0.22)) {
                        isEditingTime = true
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(displayedAlarmDate == nil ? copy.text(.noActiveAlarms) : copy.text(.nextAlarm))
                            .font(.system(.footnote, design: .rounded).weight(.bold))
                            .foregroundStyle(.blue.opacity(0.92))
                            .textCase(.uppercase)
                            .tracking(1.2)
                            .padding(.bottom, 2)

                        Text(timeText(for: displayedAlarmDate))
                            .font(.system(size: 44, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                            .foregroundStyle(.white)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background {
                                Capsule()
                                    .fill(.white.opacity(0.1))
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                                    }
                            }

                        Text(copy.text(.tapToChange))
                            .font(.system(.caption2, design: .rounded).weight(.medium))
                            .foregroundStyle(.white.opacity(0.55))

                        if let date = displayedAlarmDate {
                            Text(dateText(for: date))
                                .font(.system(.caption2, design: .rounded).weight(.medium))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(copy.text(.setOnIPhone))
                                .font(.system(.caption2, design: .rounded).weight(.medium))
                                .foregroundStyle(.secondary.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                }
                .buttonStyle(.plain)
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 0)
        .animation(.snappy(duration: 0.22), value: isEditingTime)
        .onAppear {
            applySyncedNextAlarm()
        }
        .onChange(of: internalHour) {
            guard !isApplyingSyncedAlarm else { return }
            sensorManager.markNextAlarmDraftChanged()
        }
        .onChange(of: internalMinute) {
            guard !isApplyingSyncedAlarm else { return }
            sensorManager.markNextAlarmDraftChanged()
        }
        .onChange(of: sensorManager.nextAlarmDate) {
            applySyncedNextAlarm()
        }
        // Crown rotation: rotating from the main screen (not editing) opens the picker.
        // Requires ≥3 low-sensitivity clicks to avoid accidental triggers.
        .focusable(!isEditingTime)
        .digitalCrownRotation(
            $idleCrownValue,
            from: -12,
            through: 12,
            by: 1,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: idleCrownValue) { _, newValue in
            guard !isEditingTime else {
                idleCrownValue = 0
                return
            }
            if abs(newValue) >= 3 {
                initialField = .hour
                withAnimation(.snappy(duration: 0.22)) {
                    isEditingTime = true
                }
                idleCrownValue = 0
            }
        }
        .onChange(of: isEditingTime) { _, editing in
            if editing { idleCrownValue = 0 }
        }
    }

    var buttonTitle: String {
        switch sensorManager.weeklyAlarmSyncState {
        case .saving:
            return copy.text(.syncing)
        case .saved:
            return copy.text(.saved)
        case .pending:
            return copy.text(.syncPending)
        case .unreachable:
            return copy.text(.phoneUnavailable)
        case .failed:
            return copy.text(.syncFailed)
        case .synced:
            return copy.text(.save)
        }
    }

    var buttonIconName: String {
        switch sensorManager.weeklyAlarmSyncState {
        case .saved, .synced:
            return "checkmark"
        case .saving:
            return "arrow.triangle.2.circlepath"
        case .pending:
            return "clock.arrow.circlepath"
        case .unreachable, .failed:
            return "exclamationmark.triangle"
        }
    }

    var buttonTint: Color {
        switch sensorManager.weeklyAlarmSyncState {
        case .saved, .synced:
            return .green
        case .saving:
            return .blue
        case .pending:
            return .yellow
        case .unreachable, .failed:
            return .red
        }
    }

    var displayedAlarmDate: Date? {
        switch sensorManager.weeklyAlarmSyncState {
        case .saving, .pending, .unreachable:
            return wakeTime
        case .synced, .saved, .failed:
            return sensorManager.nextAlarmDate
        }
    }

    static func defaultWakeTime() -> Date {
        var components = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: Date())
        components.hour = 7
        components.minute = 0
        components.second = 0
        return Calendar.autoupdatingCurrent.date(from: components) ?? Date()
    }

    func applySyncedNextAlarm() {
        guard let nextAlarmDate = sensorManager.nextAlarmDate else {
            if sensorManager.weeklyAlarmSyncState != .saving {
                withAnimation(.snappy(duration: 0.18)) {
                    isEditingTime = false
                }
            }
            return
        }

        let calendar = Calendar.autoupdatingCurrent
        let syncedHour = calendar.component(.hour, from: nextAlarmDate)
        let syncedMinute = calendar.component(.minute, from: nextAlarmDate)

        isApplyingSyncedAlarm = true
        
        let newDate = Self.todayDate(hour: syncedHour, minute: syncedMinute)
        withAnimation(.snappy(duration: 0.22)) {
            wakeTime = newDate
            internalHour = syncedHour
            internalMinute = syncedMinute
        }

        DispatchQueue.main.async {
            isApplyingSyncedAlarm = false
        }

        if sensorManager.weeklyAlarmSyncState != .saving {
            withAnimation(.snappy(duration: 0.18)) {
                isEditingTime = false
            }
        }
    }

    func updateWakeTimeFromInternal() {
        wakeTime = Self.todayDate(hour: internalHour, minute: internalMinute)
    }

    static func todayDate(hour: Int, minute: Int) -> Date {
        var components = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.autoupdatingCurrent.date(from: components) ?? Date()
    }

    func cancelEditing() {
        applySyncedNextAlarm()
        withAnimation(.snappy(duration: 0.22)) {
            isEditingTime = false
        }
    }


    func dateText(for date: Date) -> String {
        return date.formatted(
            .dateTime
                .weekday(.abbreviated)
                .day()
                .month(.abbreviated)
                .locale(Locale.autoupdatingCurrent)
        )
    }

    func timeText(for date: Date?) -> String {
        guard let date else { return "--:--" }
        return date.formatted(
            Date.FormatStyle()
                .locale(Locale.autoupdatingCurrent)
                .hour()
                .minute()
        )
    }
}
