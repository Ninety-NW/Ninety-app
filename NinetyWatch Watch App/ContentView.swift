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
                sensorManager.recoverMonitoringIfNeeded(reason: "view recovery")
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

struct WatchSingleAlarmView: View {
    @ObservedObject var sensorManager: WatchSensorManager
    @Binding var isEditingTime: Bool
    @Binding var showDiagnostics: Bool

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
            syncDraftFromCurrentAlarm()
        }
        .onChange(of: sensorManager.nextAlarmDate) {
            guard !isEditingTime else { return }
            syncDraftFromCurrentAlarm()
        }
    }

    var displayView: some View {
        ZStack {
            Button {
                openEditor()
            } label: {
                VStack(spacing: 8) {
                    Text(sensorManager.nextAlarmDate == nil ? "Sveglia" : "Sveglia impostata")
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))

                    Text(timeText(for: sensorManager.nextAlarmDate))
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
        }
        .overlay(alignment: .bottomTrailing) {
            diagnosticButton
                .padding(.trailing, 12)
                .padding(.bottom, 14)
        }
    }

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

    var subtitleText: String {
        guard let date = sensorManager.nextAlarmDate else { return "-" }
        return date.formatted(
            .dateTime
                .weekday(.abbreviated)
                .day()
                .month(.abbreviated)
                .locale(Locale.autoupdatingCurrent)
        )
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

    func openEditor() {
        syncDraftFromCurrentAlarm()
        withAnimation(.snappy(duration: 0.22)) {
            isEditingTime = true
        }
    }

    func cancelEditing() {
        syncDraftFromCurrentAlarm()
        withAnimation(.snappy(duration: 0.22)) {
            isEditingTime = false
        }
    }

    func deleteAlarm() {
        sensorManager.deleteCurrentAlarmFromWatch()
        syncDraftFromCurrentAlarm()
        withAnimation(.snappy(duration: 0.22)) {
            isEditingTime = false
        }
    }

    func saveAlarm() {
        let minute = roundedFiveMinute(draftMinute)
        sensorManager.setNextAlarm(
            hour: draftPeriod.hourOffset + normalizedDraftHour,
            minute: minute
        )
        withAnimation(.snappy(duration: 0.22)) {
            isEditingTime = false
        }
    }

    func syncDraftFromCurrentAlarm() {
        guard let date = sensorManager.nextAlarmDate else {
            draftHour = 7
            draftMinute = 0
            draftPeriod = .am
            return
        }

        let calendar = Calendar.autoupdatingCurrent
        let hour = calendar.component(.hour, from: date)
        draftHour = hour % 12
        draftMinute = roundedFiveMinute(calendar.component(.minute, from: date))
        draftPeriod = hour >= 12 ? .pm : .am
    }

    func defaultDraftDate() -> Date {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let roundedMinute = Int(ceil(Double(calendar.component(.minute, from: now)) / 5.0) * 5.0)
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        components.minute = roundedMinute % 60
        components.second = 0
        let base = calendar.date(from: components) ?? now
        if roundedMinute >= 60 {
            return calendar.date(byAdding: .hour, value: 1, to: base) ?? base
        }
        return base
    }

    func roundedFiveMinute(_ minute: Int) -> Int {
        min(55, max(0, Int(round(Double(minute) / 5.0) * 5.0)))
    }

    var normalizedDraftHour: Int {
        ((draftHour % 12) + 12) % 12
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
