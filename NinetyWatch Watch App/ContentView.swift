import SwiftUI

struct ContentView: View {
    @StateObject var sensorManager = WatchSensorManager.shared
    @StateObject var hapticManager = HapticWakeUpManager.shared
    @State var isEditingTime = false
    @State var showDiagnostics = false

    var body: some View {
        NavigationStack {
            ZStack {
                WatchPageBackground()

                WatchSingleAlarmView(
                    sensorManager: sensorManager,
                    isEditingTime: $isEditingTime,
                    showDiagnostics: $showDiagnostics
                )

                if !isEditingTime {
                    VStack {
                        Spacer()
                        WatchStatusFooter(sensorManager: sensorManager)
                            .padding(.bottom, -2)
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

struct WatchStatusFooter: View {
    @ObservedObject var sensorManager: WatchSensorManager

    var isWatchOnly: Bool {
        sensorManager.connectionStatus.contains("Watch only") ||
            sensorManager.connectionStatus.contains("Phone sync disabled")
    }

    var isSynced: Bool {
        sensorManager.connectionStatus.contains("reachable") ||
            sensorManager.connectionStatus.contains("enabled") ||
            isWatchOnly
    }

    var statusText: String {
        if isWatchOnly {
            return "Watch only"
        } else if isSynced {
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
                .foregroundStyle(.secondary.opacity(0.85))
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

enum AlarmPeriod {
    case am
    case pm

    var title: String {
        switch self {
        case .am: return "AM"
        case .pm: return "PM"
        }
    }

    var hourOffset: Int {
        switch self {
        case .am: return 0
        case .pm: return 12
        }
    }

    mutating func toggle() {
        self = self == .am ? .pm : .am
    }
}

// MARK: - Alarm Setup (Main UI + Test Logic)

struct WatchSingleAlarmView: View {
    @ObservedObject var sensorManager: WatchSensorManager
    @Binding var isEditingTime: Bool
    @Binding var showDiagnostics: Bool

    // --- State from Test (logic) ---
    @State var wakeTime = WatchSingleAlarmView.defaultWakeTime()
    @State var internalHour = 7
    @State var internalMinute = 0
    @State var isApplyingSyncedAlarm = false
    @State var idleCrownValue: Double = 0
    @FocusState private var isButtonFocused: Bool

    // --- State for CircularAlarmDial (Main UI) ---
    @State var draftHour = 7
    @State var draftMinute = 0
    @State var draftPeriod: AlarmPeriod = .am

    var body: some View {
        ZStack {
            if isEditingTime {
                editingView
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                displayView
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.22), value: isEditingTime)
        .onAppear {
            applySyncedNextAlarm()
            if !isEditingTime {
                isButtonFocused = true
            }
        }
        // --- Test logic: guard against feedback loops ---
        .onChange(of: draftHour) {
            guard !isApplyingSyncedAlarm else { return }
            syncInternalFromDraft()
            sensorManager.markNextAlarmDraftChanged()
        }
        .onChange(of: draftMinute) {
            guard !isApplyingSyncedAlarm else { return }
            syncInternalFromDraft()
            sensorManager.markNextAlarmDraftChanged()
        }
        .onChange(of: draftPeriod) {
            guard !isApplyingSyncedAlarm else { return }
            syncInternalFromDraft()
            sensorManager.markNextAlarmDraftChanged()
        }
        .onChange(of: sensorManager.nextAlarmDate) { old, new in
            guard old != new else { return }
            applySyncedNextAlarm()
        }
        .onChange(of: isEditingTime) { _, editing in
            idleCrownValue = 0
            if !editing {
                isButtonFocused = true
            }
        }
    }

    // MARK: - Display View (from Main)

    var displayView: some View {
        ZStack {
            Button {
                openEditor()
            } label: {
                VStack(spacing: 8) {
                    Text(sensorManager.nextAlarmDate == nil ? "Sveglia" : "Sveglia impostata")
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))

                    Text(timeText(for: displayedAlarmDate))
                        .font(.system(size: 50, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(.white)

                    Text(subtitleText)
                        .font(.system(.caption2, design: .rounded).weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($isButtonFocused)
            .focusable(true)
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
                if abs(newValue) >= 3 {
                    openEditor()
                    idleCrownValue = 0
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            diagnosticButton
                .padding(.trailing, 12)
                .padding(.bottom, 14)
        }
    }

    // MARK: - Editing View (from Main)

    var editingView: some View {
        GeometryReader { proxy in
            let buttonSize: CGFloat = 32
            let edgeInset: CGFloat = 12
            let cornerCenter = buttonSize / 2 + edgeInset
            let viewCenter = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let buttonCenters = [
                CGPoint(x: cornerCenter, y: cornerCenter),
                CGPoint(x: cornerCenter, y: proxy.size.height - cornerCenter),
                CGPoint(x: proxy.size.width - cornerCenter, y: proxy.size.height - cornerCenter)
            ]
            let nearestButtonDistance = buttonCenters
                .map { hypot($0.x - viewCenter.x, $0.y - viewCenter.y) }
                .min() ?? min(proxy.size.width, proxy.size.height) / 2
            let dialClearance: CGFloat = 5
            let dialRadius = min(
                min(proxy.size.width, proxy.size.height) / 2 - 3,
                nearestButtonDistance - buttonSize / 2 - dialClearance
            )
            let dialSide = max(0, dialRadius * 2)

            ZStack {
                CircularAlarmDial(hour: $draftHour, minute: $draftMinute, period: $draftPeriod)
                    .frame(width: dialSide, height: dialSide)
                    .position(viewCenter)

                roundIconButton(systemName: "xmark", tint: .white.opacity(0.92), fill: .white.opacity(0.12)) {
                    cancelEditing()
                }
                .position(x: cornerCenter, y: cornerCenter)

                roundIconButton(systemName: "trash", tint: .red, fill: .red.opacity(0.14)) {
                    deleteAlarm()
                }
                .position(x: cornerCenter, y: proxy.size.height - cornerCenter)

                roundIconButton(systemName: "checkmark", tint: .white, fill: .green) {
                    saveAlarm()
                }
                .position(x: proxy.size.width - cornerCenter, y: proxy.size.height - cornerCenter)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .all)
    }

    // MARK: - Computed Properties

    var subtitleText: String {
        guard let date = displayedAlarmDate else { return "-" }
        return date.formatted(
            .dateTime
                .weekday(.abbreviated)
                .day()
                .month(.abbreviated)
                .locale(Locale.autoupdatingCurrent)
        )
    }

    /// Show the locally-drafted time during save/pending states (from Test),
    /// otherwise show the confirmed nextAlarmDate.
    var displayedAlarmDate: Date? {
        switch sensorManager.weeklyAlarmSyncState {
        case .saving, .pending, .unreachable:
            return wakeTime
        case .synced, .saved, .failed:
            return sensorManager.nextAlarmDate
        }
    }

    var diagnosticButton: some View {
        Button {
            showDiagnostics = true
        } label: {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.86))
        .contentShape(Circle())
        .background {
            Circle()
                .fill(.white.opacity(0.08))
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
                }
        }
    }

    func roundIconButton(
        systemName: String,
        tint: Color,
        fill: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .contentShape(Circle())
        .background {
            Circle()
                .fill(fill)
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.16), lineWidth: 0.7)
                }
        }
    }

    // MARK: - Actions

    func openEditor() {
        syncDraftFromInternal()
        withAnimation(.snappy(duration: 0.22)) {
            isEditingTime = true
        }
    }

    func cancelEditing() {
        applySyncedNextAlarm()
        withAnimation(.snappy(duration: 0.22)) {
            isEditingTime = false
        }
    }

    func deleteAlarm() {
        sensorManager.stopActiveAlarmFromWatch()
        applySyncedNextAlarm()
        withAnimation(.snappy(duration: 0.22)) {
            isEditingTime = false
        }
    }

    func saveAlarm() {
        syncInternalFromDraft()
        updateWakeTimeFromInternal()
        sensorManager.setNextAlarm(wakeTime: wakeTime)
        withAnimation(.snappy(duration: 0.22)) {
            isEditingTime = false
        }
    }

    // MARK: - Sync Logic (from Test)

    /// Bridge: CircularAlarmDial draft (12h) → internal state (24h)
    func syncInternalFromDraft() {
        let normalized12h = ((draftHour % 12) + 12) % 12
        internalHour = draftPeriod.hourOffset + normalized12h
        internalMinute = draftMinute
    }

    /// Bridge: internal state (24h) → CircularAlarmDial draft (12h)
    func syncDraftFromInternal() {
        draftHour = internalHour % 12
        draftMinute = internalMinute
        draftPeriod = internalHour >= 12 ? .pm : .am
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

        // Guard: avoid writing state when nothing has changed.
        // This breaks the onChange(nextAlarmDate) → applySyncedNextAlarm →
        // write internalHour → onChange(internalHour) feedback loop that was
        // causing hundreds of Crown Sequencer re-registrations and the
        // AttributeGraph cycle warnings.
        guard syncedHour != internalHour || syncedMinute != internalMinute else {
            if sensorManager.weeklyAlarmSyncState != .saving {
                withAnimation(.snappy(duration: 0.18)) {
                    isEditingTime = false
                }
            }
            return
        }

        isApplyingSyncedAlarm = true

        let newDate = Self.todayDate(hour: syncedHour, minute: syncedMinute)
        withAnimation(.snappy(duration: 0.22)) {
            wakeTime = newDate
            internalHour = syncedHour
            internalMinute = syncedMinute
        }
        syncDraftFromInternal()

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

    static func defaultWakeTime() -> Date {
        var components = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: Date())
        components.hour = 7
        components.minute = 0
        components.second = 0
        return Calendar.autoupdatingCurrent.date(from: components) ?? Date()
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

struct WatchSingleAlarmContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
