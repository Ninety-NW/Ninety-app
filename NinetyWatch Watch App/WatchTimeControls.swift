import SwiftUI

struct TimeWheelField: View {
    @Binding var hour: Int
    @Binding var minute: Int
    let initialFocus: WatchTimeField

    @State var focusedField: WatchTimeField
    @State var crownValue: Double = 0

    init(hour: Binding<Int>, minute: Binding<Int>, initialFocus: WatchTimeField) {
        _hour = hour
        _minute = minute
        self.initialFocus = initialFocus
        _focusedField = State(initialValue: initialFocus)
    }

    var selectedValue: Int {
        focusedField == .hour ? hour : minute
    }

    var selectedRange: ClosedRange<Double> {
        focusedField == .hour ? 0...23 : 0...59
    }

    var body: some View {
        HStack(spacing: 8) {
            WatchCustomWheelPicker(selectedValue: $hour, range: 0...23, isFocused: focusedField == .hour) {
                focusedField = .hour
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = .hour
            }
            
            Text(":")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .opacity(0.5)
                .padding(.bottom, 2)

            WatchCustomWheelPicker(selectedValue: $minute, range: 0...59, isFocused: focusedField == .minute) {
                focusedField = .minute
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = .minute
            }
        }
        .frame(height: 100)
        .padding(.horizontal, 10)
        .background {
            Capsule()
                .fill(.white.opacity(0.08))
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
                }
        }
        .clipShape(Capsule())
        .onAppear {
            focusedField = initialFocus
            crownValue = Double(selectedValue)
        }
        .onChange(of: focusedField) { _, _ in
            crownValue = Double(selectedValue)
        }
        .onChange(of: hour) { _, newHour in
            guard focusedField == .hour else { return }
            crownValue = Double(newHour)
        }
        .onChange(of: minute) { _, newMinute in
            guard focusedField == .minute else { return }
            crownValue = Double(newMinute)
        }
        .onChange(of: crownValue) { _, newCrown in
            let rounded = Int(round(newCrown))
            switch focusedField {
            case .hour:
                if rounded != hour {
                    hour = rounded
                }
            case .minute:
                if rounded != minute {
                    minute = rounded
                }
            }
        }
        .focusable(true)
        .digitalCrownRotation(
            $crownValue,
            from: selectedRange.lowerBound,
            through: selectedRange.upperBound,
            by: 1,
            sensitivity: .low,
            isContinuous: true,
            isHapticFeedbackEnabled: true
        )
    }
}

struct WatchCustomWheelPicker: View {
    @Binding var selectedValue: Int
    let range: ClosedRange<Int>
    var isFocused: Bool = false
    var onTap: (() -> Void)? = nil
    
    @State var viewPosition: Int?
    @State var userDidScroll = false
    
    let multiplier = 3
    var count: Int { range.upperBound - range.lowerBound + 1 }
    let itemHeight: CGFloat = 34
    let containerHeight: CGFloat = 100

    var body: some View {
        ZStack {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(0..<(count * multiplier), id: \.self) { index in
                        let value = range.lowerBound + (index % count)

                        Text(String(format: "%02d", value))
                            .font(.system(size: 28, weight: isFocused ? .semibold : .light, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(height: itemHeight)
                            .foregroundStyle(isFocused ? Color.blue : Color.white.opacity(0.8))
                            .scrollTransition(axis: .vertical) { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1.0 : 0.55)
                                    .scaleEffect(phase.isIdentity ? 1.0 : 0.85)
                                    .rotation3DEffect(
                                        .degrees(Double(phase.value) * -20),
                                        axis: (x: 1, y: 0, z: 0),
                                        perspective: 0.5
                                    )
                            }
                            .id(index)
                    }
                }
                .frame(maxWidth: .infinity)
                .scrollTargetLayout()
                .contentShape(Rectangle())
                .onTapGesture {
                    onTap?()
                }
            }
            .safeAreaPadding(.vertical, (containerHeight - itemHeight) / 2)
            .scrollPosition(id: $viewPosition, anchor: .center)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .onScrollPhaseChange { _, newPhase in
                if newPhase == .interacting {
                    userDidScroll = true
                } else if newPhase == .idle {
                    userDidScroll = false
                    if let pos = viewPosition {
                        let newValue = range.lowerBound + (pos % count)
                        if newValue != selectedValue {
                            selectedValue = newValue
                        }
                    }
                }
            }
            .onChange(of: viewPosition) { _, newPos in
                guard let new = newPos else { return }
                let newValue = range.lowerBound + (new % count)
                if userDidScroll && newValue != selectedValue {
                    selectedValue = newValue
                    WKInterfaceDevice.current().play(.click)
                }
            }
            .onChange(of: selectedValue) { _, newSelected in
                if !userDidScroll, let currentPos = viewPosition {
                    let currentShownValue = range.lowerBound + (currentPos % count)
                    if currentShownValue != newSelected {
                        var diff = newSelected - currentShownValue
                        let half = count / 2
                        if diff > half {
                            diff -= count
                        } else if diff < -half {
                            diff += count
                        }
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                            viewPosition = currentPos + diff
                        }
                    }
                }
            }
            .onAppear {
                let midIndexOrigin = (multiplier / 2) * count
                let offset = selectedValue - range.lowerBound
                viewPosition = midIndexOrigin + offset
            }
        }
        .frame(height: containerHeight)
    }
}

struct SoftControlBackground: View {
    let cornerRadius: CGFloat
    var horizontalEdgesOnly = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.05),
                        Color(red: 0.08, green: 0.13, blue: 0.24).opacity(0.22),
                        Color.white.opacity(0.018)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(edgeOverlay)
            .shadow(color: Color(red: 0.1, green: 0.18, blue: 0.35).opacity(0.08), radius: 10, x: 0, y: 0)
    }

    @ViewBuilder
    var edgeOverlay: some View {
        if horizontalEdgesOnly {
            VStack(spacing: 0) {
                horizontalEdge
                Spacer(minLength: 0)
                horizontalEdge.opacity(0.55)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.blue.opacity(0.025),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.7
                )
        }
    }

    var horizontalEdge: some View {
        LinearGradient(
            colors: [
                Color.clear,
                Color.white.opacity(0.07),
                Color.white.opacity(0.07),
                Color.clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 0.7)
    }
}

// MARK: - Debug View

#if DEBUG
struct DebugNodeView: View {
    @ObservedObject var sensorManager: WatchSensorManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("🛠 Debug Node")
                    .font(.headline)
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session: \(sensorManager.sessionState)")
                        .foregroundColor(.blue)
                    Text("Link: \(sensorManager.connectionStatus)")
                        .foregroundColor(.secondary)
                    
                    if sensorManager.hasPendingSchedule, let pending = sensorManager.pendingScheduleDescription {
                        Text("Queue: \(pending)")
                            .foregroundColor(.orange)
                    }

                    if sensorManager.hasReadySchedule, let ready = sensorManager.readyScheduleDescription {
                        Text("Ready: \(ready)")
                            .foregroundColor(.green)
                    }
                }
                .font(.caption2)
                
                Divider()
                
                if !sensorManager.lastPayloadSent.isEmpty {
                    Text("Last Payload:")
                        .font(.caption2.bold())
                    Text(sensorManager.lastPayloadSent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Manual overrides for testing routing
                Group {
                    Button("Simulate Start (5s)") {
                        sensorManager.scheduleSmartAlarmSession(at: Date().addingTimeInterval(5))
                    }
                    .tint(.green)
                    
                    Button("Force Stop Session") {
                        sensorManager.stopSession()
                    }
                    .tint(.red)
                }
                .font(.caption)
            }
            .padding()
        }
    }
}
#endif

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
