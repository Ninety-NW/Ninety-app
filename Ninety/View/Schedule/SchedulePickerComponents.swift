import SwiftUI

struct IdleTimeDisplay: View {
    let hour: Int
    let minute: Int
    let isActive: Bool

    var hourText: String { String(format: "%02d", hour) }
    var minuteText: String { String(format: "%02d", minute) }

    var body: some View {
        HStack(spacing: 12) {
            timeUnit(hourText)

            Text(":")
                .font(.system(size: 58, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
                .opacity(isActive ? 0.72 : 0.28)
                .offset(y: -3)

            timeUnit(minuteText)
        }
        .frame(width: 286, height: 280)
    }

    @ViewBuilder
    func timeUnit(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 72, weight: .light, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: 100, height: 96)
            .foregroundStyle(.primary)
            .opacity(isActive ? 1.0 : 0.4)
    }
}

struct DayOfWeekSelector: View {
    let scheduledWeekdays: Set<Int>
    let selectedWeekday: Int
    let onSelect: (Int) -> Void
    
    @AppStorage("appLanguage") var appLanguage: String = AppLanguage.english.rawValue
    @Environment(\.colorScheme) var colorScheme
    
    var accent: Color { .scheduleAccent(for: colorScheme) }

    struct WeekdayInfo: Identifiable {
        let id: Int // 1-indexed weekday (1=Sun, 2=Mon...)
        let symbol: String
    }

    var orderedWeekdays: [WeekdayInfo] {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: appLanguage)
        let symbols = calendar.veryShortWeekdaySymbols
        let firstWeekday = calendar.firstWeekday // Usually 1 (Sun) or 2 (Mon)
        
        return (0..<7).map { i in
            let index = (firstWeekday - 1 + i) % 7
            return WeekdayInfo(id: index + 1, symbol: symbols[index])
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            ForEach(orderedWeekdays) { day in
                let isScheduled = scheduledWeekdays.contains(day.id)
                let isSelected = selectedWeekday == day.id

                Button {
                    onSelect(day.id)
                } label: {
                    Text(day.symbol)
                        .font(.footnote.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(isScheduled ? Color.white : Color.primary.opacity(0.9))
                        .background {
                            Circle()
                                .fill(isScheduled ? accent.opacity(0.25) : Color.white.opacity(0.08))
                                .overlay(
                                    Circle()
                                        .strokeBorder(isSelected ? Color.primary.opacity(0.4) : Color.clear, lineWidth: 1.5)
                                )
                                .glassEffect(.regular.tint(isScheduled ? accent : .clear), in: Circle())
                                .scaleEffect(isSelected ? 1.1 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
    }
}

struct CustomWheelPicker: View {
    @Binding var selectedValue: Int
    let range: ClosedRange<Int>
    let isMinutes: Bool
    let isActive: Bool
    let isPickerMode: Bool
    
    @State var viewPosition: Int?
    @State var userDidScroll = false
    @AppStorage("hapticFeedbackEnabled") var hapticFeedbackEnabled: Bool = true
    @Environment(\.colorScheme) var colorScheme
    let selectionHaptic = UISelectionFeedbackGenerator()
    
    // Keep enough repeated rows to feel infinite without paying for an oversized subtree on open.
    let multiplier = 3
    var count: Int { range.upperBound - range.lowerBound + 1 }
    var focusTint: Color {
        colorScheme == .light
        ? Color.black.opacity(0.06)
        : Color.white.opacity(0.08)
    }

    var body: some View {
        let baseOpacity = isActive ? 1.0 : 0.4
        let blurOpacity = isActive ? 0.3 : 0.1

        ZStack {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(0..<(count * multiplier), id: \.self) { index in
                        let value = range.lowerBound + (index % count)

                        Text(String(format: "%02d", value))
                            .font(.system(size: 72, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(height: 96)
                            .foregroundStyle(.primary)
                            .scrollTransition(axis: .vertical) { content, phase in
                                content
                                    .opacity(phase.isIdentity ? baseOpacity : (isPickerMode ? blurOpacity : 0.0))
                                    .scaleEffect(phase.isIdentity ? 1.0 : (isPickerMode ? 0.82 : 1.0))
                                    .rotation3DEffect(
                                        .degrees(Double(phase.value) * -20),
                                        axis: (x: 1, y: 0, z: 0),
                                        perspective: 0.5
                                    )
                                    .offset(y: phase.value * 12)
                            }
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .safeAreaPadding(.vertical, 66) // (Container 228 - Item 96) / 2
            .scrollPosition(id: $viewPosition, anchor: .center)
            .scrollTargetBehavior(.viewAligned)
            .onScrollPhaseChange { _, newPhase in
                if newPhase == .interacting {
                    userDidScroll = true
                    if hapticFeedbackEnabled { selectionHaptic.prepare() }
                } else if newPhase == .idle {
                    userDidScroll = false
                    // Ensure the selection matches the final idle position
                    if let pos = viewPosition {
                        let newValue = range.lowerBound + (pos % count)
                        if newValue != selectedValue {
                            selectedValue = newValue
                        }
                    }
                }
            }
            .onChange(of: viewPosition) { oldPos, newPos in
                guard let new = newPos else { return }
                let newValue = range.lowerBound + (new % count)
                
                if newValue != selectedValue {
                    // Update value while scrolling for immediate feedback
                    if userDidScroll {
                        selectedValue = newValue
                        if hapticFeedbackEnabled {
                            selectionHaptic.selectionChanged()
                            selectionHaptic.prepare()
                        }
                    }
                }
            }
            .onChange(of: selectedValue) { _, newSelected in
                if !userDidScroll, let currentPos = viewPosition {
                    let currentShownValue = range.lowerBound + (currentPos % count)
                    if currentShownValue != newSelected {
                        var diff = newSelected - currentShownValue
                        let half = count / 2
                        if diff > half { diff -= count }
                        else if diff < -half { diff += count }
                        
                        viewPosition = currentPos + diff
                    }
                }
            }
            .onAppear {
                let midIndexOrigin = (multiplier / 2) * count
                let offset = selectedValue - range.lowerBound
                viewPosition = midIndexOrigin + offset
            }
        }
    }
}

#Preview {
    ScheduleView()
        .environmentObject(ScheduleViewModel())
        .environmentObject(TourFrameStore())
}
