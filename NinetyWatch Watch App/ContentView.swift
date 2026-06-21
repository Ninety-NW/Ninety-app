import SwiftUI

// MARK: - Root View

struct ContentView: View {
    @StateObject var sensorManager = WatchSensorManager.shared
    @StateObject var hapticManager = HapticWakeUpManager.shared
    @State private var isEditingTime   = false
    @State private var showDiagnostics = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                WatchSingleAlarmView(
                    sensorManager: sensorManager,
                    isEditingTime: $isEditingTime,
                    showDiagnostics: $showDiagnostics
                )

                if !isEditingTime {
                    VStack {
                        Spacer()
                        WatchStatusFooter(sensorManager: sensorManager)
                            .padding(.bottom, 2)
                    }
                    .ignoresSafeArea(.all, edges: .bottom)
                }

                if hapticManager.isPlaying {
                    AlarmView()
                        .environmentObject(sensorManager)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(10)
                }
            }
            .containerBackground(.black.gradient, for: .navigation)
            .navigationDestination(isPresented: $showDiagnostics) {
                WatchDiagnosticsView(sensorManager: sensorManager)
            }
            .onAppear {
                sensorManager.refreshStoredAlarmStateIfNeeded()
                sensorManager.requestHealthPermissions { _ in }
            }
        }
    }
}

// MARK: - Status Footer

struct WatchStatusFooter: View {
    @ObservedObject var sensorManager: WatchSensorManager

    private var isWatchOnly: Bool {
        sensorManager.connectionStatus.contains("Watch only") ||
        sensorManager.connectionStatus.contains("Phone sync disabled")
    }
    private var isSynced: Bool {
        sensorManager.connectionStatus.contains("reachable") ||
        sensorManager.connectionStatus.contains("enabled") ||
        isWatchOnly
    }
    private var statusText: String {
        if isWatchOnly { return WatchCopy.current.text(.watchOnly) }
        if isSynced    { return WatchCopy.current.text(.synced) }
        if sensorManager.connectionStatus.contains("unavailable") {
            return WatchCopy.current.text(.phoneUnavailable)
        }
        return WatchCopy.current.text(.syncing)
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isSynced ? Color.green : Color.red)
                .frame(width: 5, height: 5)
            Text(statusText)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(.white.opacity(0.05)))
    }
}

// MARK: - AlarmPeriod

enum AlarmPeriod {
    case am, pm
    var title: String      { self == .am ? "AM" : "PM" }
    var hourOffset: Int    { self == .am ? 0 : 12 }
    mutating func toggle() { self = self == .am ? .pm : .am }
}

// MARK: - Main Alarm View

struct WatchSingleAlarmView: View {
    @ObservedObject var sensorManager: WatchSensorManager
    @Binding var isEditingTime: Bool
    @Binding var showDiagnostics: Bool

    // Internal 24h state (source of truth)
    @State private var internalHour   = 7
    @State private var internalMinute = 0
    @State private var wakeTime       = WatchSingleAlarmView.defaultWakeTime()
    @State private var isApplyingSync = false

    // Draft for picker (12h, 0–11)
    @State private var draftHour:   Int         = 7
    @State private var draftMinute: Int         = 0
    @State private var draftPeriod: AlarmPeriod = .am

    var body: some View {
        ZStack {
            if isEditingTime {
                editingView
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal:   .move(edge: .bottom).combined(with: .opacity)
                    ))
            } else {
                displayView
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.25), value: isEditingTime)
        .onAppear { applySyncedAlarm() }
        .onChange(of: sensorManager.nextAlarmDate) { old, new in
            guard old != new else { return }
            applySyncedAlarm()
        }
        .onChange(of: draftHour)   { guard !isApplyingSync else { return }; syncInternalFromDraft(); sensorManager.markNextAlarmDraftChanged() }
        .onChange(of: draftMinute) { guard !isApplyingSync else { return }; syncInternalFromDraft(); sensorManager.markNextAlarmDraftChanged() }
        .onChange(of: draftPeriod) { guard !isApplyingSync else { return }; syncInternalFromDraft(); sensorManager.markNextAlarmDraftChanged() }
    }

    // MARK: Display View

    var displayView: some View {
        ScrollView {
            VStack(spacing: 10) {

                // ── Time card ────────────────────────────────────────
                Button { openEditor() } label: {
                    HStack(alignment: .center, spacing: 4) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(
                                sensorManager.nextAlarmDate == nil
                                    ? WatchCopy.current.text(.alarm)
                                    : WatchCopy.current.text(.scheduled),
                                systemImage: "alarm.fill"
                            )
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(sensorManager.nextAlarmDate != nil ? .green : .secondary)

                            Text(timeText(for: displayedAlarmDate))
                                .font(.system(size: 44, weight: .regular, design: .rounded))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .foregroundStyle(.white)

                            Text(subtitleText)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 4)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBackground(tint: .white))
                }
                .buttonStyle(.plain)

                // ── Smart window card ─────────────────────────────────
                if alarmIsSet {
                    SmartWindowCard(alarmDate: displayedAlarmDate)

                    // ── Delete Alarm button ───────────────────────────
                    Button(action: deleteAlarm) {
                        Label(WatchCopy.current.text(.deleteAlarm), systemImage: "trash.fill")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.red.opacity(0.12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(Color.red.opacity(0.25), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }

                // ── Diagnostics ───────────────────────────────────────
                Button { showDiagnostics = true } label: {
                    Label("Diagnostics", systemImage: "waveform.path.ecg")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
    }

    // MARK: Editing View

    var editingView: some View {
        VStack(spacing: 12) {
            Text("Set Alarm")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            DigitalTimePickerView(
                hour:     $draftHour,
                minute:   $draftMinute,
                period:   $draftPeriod,
                onCancel: cancelEditing,
                onSave:   saveAlarm
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 4)
    }

    // MARK: Helpers

    private var alarmIsSet: Bool {
        sensorManager.nextAlarmDate != nil ||
        sensorManager.weeklyAlarmSyncState == .saving ||
        sensorManager.weeklyAlarmSyncState == .pending
    }

    var displayedAlarmDate: Date? {
        switch sensorManager.weeklyAlarmSyncState {
        case .saving, .pending, .unreachable: return wakeTime
        case .synced, .saved, .failed:        return sensorManager.nextAlarmDate
        }
    }

    var subtitleText: String {
        guard let date = displayedAlarmDate else { return "Tap to set" }
        return date.formatted(
            .dateTime
                .weekday(.abbreviated).day().month(.abbreviated)
                .locale(Locale.autoupdatingCurrent)
        )
    }

    func timeText(for date: Date?) -> String {
        guard let date else { return "--:--" }
        return date.formatted(
            Date.FormatStyle()
                .locale(Locale.autoupdatingCurrent)
                .hour().minute()
        )
    }

    private func cardBackground(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(tint.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(tint.opacity(0.1), lineWidth: 1)
            )
    }

    // MARK: Actions

    func openEditor() {
        syncDraftFromInternal()
        withAnimation(.snappy(duration: 0.25)) { isEditingTime = true }
    }
    func cancelEditing() {
        applySyncedAlarm()
        withAnimation(.snappy(duration: 0.25)) { isEditingTime = false }
    }
    func deleteAlarm() {
        sensorManager.stopActiveAlarmFromWatch()
        applySyncedAlarm()
        withAnimation(.snappy(duration: 0.25)) { isEditingTime = false }
    }
    func saveAlarm() {
        syncInternalFromDraft()
        updateWakeTime()
        sensorManager.setNextAlarm(wakeTime: wakeTime)
        withAnimation(.snappy(duration: 0.25)) { isEditingTime = false }
    }

    // MARK: 12h ↔ 24h Bridge

    func syncInternalFromDraft() {
        let h12      = ((draftHour % 12) + 12) % 12
        internalHour   = draftPeriod.hourOffset + h12
        internalMinute = draftMinute
    }
    func syncDraftFromInternal() {
        draftHour   = internalHour % 12
        draftMinute = internalMinute
        draftPeriod = internalHour >= 12 ? .pm : .am
    }

    func applySyncedAlarm() {
        guard let alarmDate = sensorManager.nextAlarmDate else {
            if sensorManager.weeklyAlarmSyncState != .saving {
                withAnimation(.snappy(duration: 0.18)) { isEditingTime = false }
            }
            return
        }
        let cal = Calendar.autoupdatingCurrent
        let h = cal.component(.hour,   from: alarmDate)
        let m = cal.component(.minute, from: alarmDate)
        guard h != internalHour || m != internalMinute else {
            if sensorManager.weeklyAlarmSyncState != .saving {
                withAnimation(.snappy(duration: 0.18)) { isEditingTime = false }
            }
            return
        }
        isApplyingSync = true
        withAnimation(.snappy(duration: 0.22)) {
            wakeTime      = Self.todayDate(hour: h, minute: m)
            internalHour  = h
            internalMinute = m
        }
        syncDraftFromInternal()
        DispatchQueue.main.async { isApplyingSync = false }
        if sensorManager.weeklyAlarmSyncState != .saving {
            withAnimation(.snappy(duration: 0.18)) { isEditingTime = false }
        }
    }

    func updateWakeTime() {
        wakeTime = Self.todayDate(hour: internalHour, minute: internalMinute)
    }

    static func todayDate(hour: Int, minute: Int) -> Date {
        var c = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour; c.minute = minute; c.second = 0
        return Calendar.autoupdatingCurrent.date(from: c) ?? Date()
    }
    static func defaultWakeTime() -> Date { todayDate(hour: 7, minute: 0) }
}

// MARK: - Smart Window Card
// NOTE: No repeatForever animations — they peg the watchOS render loop at 96% CPU.

struct SmartWindowCard: View {
    var alarmDate: Date?

    private var startDate: Date {
        (alarmDate ?? Date()).addingTimeInterval(-1800)
    }

    private func fmt(_ d: Date?) -> String {
        guard let d else { return "--:--" }
        return d.formatted(Date.FormatStyle().locale(Locale.autoupdatingCurrent).hour().minute())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Header
            HStack(spacing: 6) {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 13))
                Text("Smart Wake Window")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }

            // Gradient bar (static — no animation to avoid CPU spin)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 8)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.4), Color.green],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 8)

                // Deadline dot at trailing edge with a subtle bell icon
                HStack {
                    Spacer()
                    Circle()
                        .fill(Color.green)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Image(systemName: "bell.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.black)
                        )
                        .overlay(Circle().strokeBorder(.black.opacity(0.6), lineWidth: 1.5))
                        .shadow(color: .green.opacity(0.5), radius: 3)
                }
            }

            // Time labels
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(fmt(startDate))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("Monitoring starts")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(fmt(alarmDate))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    Text("Hard deadline")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.green.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.green.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.green.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

// MARK: - Previews

struct ContentView_WatchMain_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
