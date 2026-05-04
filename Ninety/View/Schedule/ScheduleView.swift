//
//  ScheduleView.swift
//  Ninety
//
//  Created by Deimante Valunaite on 08/07/2024.
//
import SwiftUI

struct ScheduleView: View {
    enum WatchSetupState: Int {
        case needsAction = 1
        case ready = 2
        case active = 3
    }

    struct WatchSetupSummary {
        let state: WatchSetupState
        let title: String
        let message: String
        let badge: String
        let symbol: String
        let tint: Color
    }

    var timeBlockOffset: CGFloat { showingWakeTimePicker ? -30 : -90 }
    let daySelectorOffset: CGFloat = 70
    let alarmButtonBottomPadding: CGFloat = 64
    let watchBannerSlotHeight: CGFloat = 190

    @EnvironmentObject var viewModel: ScheduleViewModel
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var sleepManager = SleepSessionManager.shared
    @State var showingSettings = false
    @State var isSettingsNavigationPending = false
    @State var showingDiagnostics = false
    @State var showingWakeTimePicker = false
    @Namespace var glassNamespace
    @State var internalHour: Int = 0
    @State var internalMinute: Int = 0
    @AppStorage("appLanguage") var appLanguage: String = AppLanguage.english.rawValue
    @AppStorage("hapticFeedbackEnabled") var hapticFeedbackEnabled: Bool = true
    @AppStorage("showGuidedTour") var showGuidedTour: Bool = false
    @State var showingWatchDetails = false
    let impactHaptic = UIImpactFeedbackGenerator(style: .medium)
    var accent: Color { .scheduleAccent(for: colorScheme) }
    var isSelectedDayActive: Bool { viewModel.isAlarmEnabledForSelectedDay }
    var effectiveScheduledSession: SmartAlarmManager.ScheduledSleepSession? {
        viewModel.lastScheduledSession ?? viewModel.nextUpcomingSession
    }
    var timePillTint: Color {
        guard isSelectedDayActive else { return .clear }
        return accent.opacity(colorScheme == .light ? 0.30 : 0.34)
    }
    var timeCardBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .light
            ? [
                Color.white.opacity(0.76),
                accent.opacity(0.08)
            ]
            : [
                Color.white.opacity(0.07),
                accent.opacity(0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    var watchSetupSummary: WatchSetupSummary? {
        guard viewModel.isAlarmEnabled, let scheduledSession = effectiveScheduledSession else {
            return nil
        }

        if sleepManager.isTrackingLive {
            return WatchSetupSummary(
                state: .active,
                title: "Tracking active on Apple Watch".localized(for: appLanguage),
                message: "The sleep window is running on Apple Watch now.".localized(for: appLanguage),
                badge: "Tracking in progress".localized(for: appLanguage),
                symbol: "waveform.path.ecg",
                tint: Color(red: 0.22, green: 0.72, blue: 0.55)
            )
        }

        if let readyStartDate = sleepManager.watchReadyStartDate {
            let formatted = readyStartDate.formatted(date: .omitted, time: .shortened)
            return WatchSetupSummary(
                state: .ready,
                title: "Smart Alarm ready".localized(for: appLanguage),
                message: String(
                    format: "Apple Watch will start sleep tracking at %@.".localized(for: appLanguage),
                    formatted
                ),
                badge: "Ready".localized(for: appLanguage),
                symbol: "checkmark.circle.fill",
                tint: Color(red: 0.18, green: 0.70, blue: 0.48)
            )
        }

        let pendingStartDate = sleepManager.watchQueuedStartDate ?? scheduledSession.monitoringStartDate
        let formatted = pendingStartDate.formatted(date: .omitted, time: .shortened)
        return WatchSetupSummary(
            state: .needsAction,
            title: "Open the Watch app to finish setting up".localized(for: appLanguage),
            message: String(
                format: "Open Ninety once on your Apple Watch before sleep. No extra tap is needed after that. Tracking starts at %@.".localized(for: appLanguage),
                formatted
            ),
            badge: "Open Watch".localized(for: appLanguage),
            symbol: "applewatch",
            tint: accent
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HorizonBackground(isActive: viewModel.isAlarmEnabled, accentOverride: accent)
                    .ignoresSafeArea()
                if showingWakeTimePicker {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            syncInternalTime()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                showingWakeTimePicker = false
                            }
                        }
                        .ignoresSafeArea()
                }
                VStack(spacing: 0) {
                    Spacer().frame(height: 60)
                    ZStack {
                        if !showingWakeTimePicker {
                            Text("Wake up by".localized(for: appLanguage))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .tracking(0.5)
                                .foregroundStyle(.primary.opacity(0.8))
                                .offset(y: -82)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity.combined(with: .move(edge: .bottom))
                                ))
                        }

                        RoundedRectangle(cornerRadius: 38, style: .continuous)
                            .fill(Color(white: 0.5).opacity(0.001))
                            .glassEffect(
                                .regular.interactive().tint(timePillTint),
                                in: RoundedRectangle(cornerRadius: 38, style: .continuous)
                            )
                            .glassEffectID("timePill", in: glassNamespace)
                            .frame(width: 286, height: 96)
                            .background {
                                RoundedRectangle(cornerRadius: 38, style: .continuous)
                                    .fill(timeCardBackground)
                                    .frame(width: 286, height: 96)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 38, style: .continuous)
                                    .strokeBorder(
                                        Color.white.opacity(colorScheme == .light ? 0.45 : 0.10),
                                        lineWidth: 0.8
                                    )
                                    .frame(width: 286, height: 96)
                            }
                            .tourTarget(.clockPill)
                        if showingWakeTimePicker {
                            ZStack {

                                HStack(spacing: 12) {
                                    CustomWheelPicker(
                                        selectedValue: $internalHour,
                                        range: 0...23,
                                        isMinutes: false,
                                        isActive: true,
                                        isPickerMode: true
                                    )
                                        .frame(width: 100)
                                    Text(":")
                                        .font(.system(size: 58, weight: .regular, design: .rounded))
                                        .foregroundStyle(.primary)
                                        .opacity(0.72)
                                        .offset(y: -3)
                                    CustomWheelPicker(
                                        selectedValue: $internalMinute,
                                        range: 0...59,
                                        isMinutes: true,
                                        isActive: true,
                                        isPickerMode: true
                                    )
                                        .frame(width: 100)
                                }
                                .frame(height: 228)
                                .mask(
                                    LinearGradient(
                                        stops: [
                                            .init(color: .clear, location: 0),
                                            .init(color: .black, location: 0.25),
                                            .init(color: .black, location: 0.75),
                                            .init(color: .clear, location: 1)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            }
                            .frame(width: 286, height: 280)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity.combined(with: .move(edge: .bottom))
                            ))
                            .transaction { transaction in
                                transaction.animation = nil
                            }
                        } else {
                            VStack(spacing: 0) {
                                IdleTimeDisplay(
                                    hour: internalHour,
                                    minute: internalMinute,
                                    isActive: isSelectedDayActive
                                )
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity.combined(with: .move(edge: .bottom))
                                ))
                                
                                if let summary = watchSetupSummary, isSelectedDayActive {
                                    Button {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            showingWatchDetails.toggle()
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(summary.tint)
                                                .frame(width: 8, height: 8)
                                            
                                            Text(summary.badge)
                                                .font(.system(.subheadline, design: .rounded))
                                                .fontWeight(.medium)
                                            
                                            Image(systemName: "chevron.up.circle.fill")
                                                .font(.caption2)
                                                .opacity(0.3)
                                                .rotationEffect(.degrees(showingWatchDetails ? 180 : 0))
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background {
                                            Capsule()
                                                .fill(.ultraThinMaterial)
                                                .overlay {
                                                    Capsule()
                                                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                                                }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, -80) // Pull it closer to the clock
                                }
                            }
                        }
                    }
                    .frame(width: 286, height: 280)
                    .disabled(showGuidedTour)
                    .offset(y: timeBlockOffset)
                    .overlay(alignment: .top) {
                        if !showingWakeTimePicker && !showGuidedTour {
                            Color.clear
                                .frame(width: 270, height: 130)
                                .contentShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        showingWakeTimePicker = true
                                    }
                                }
                        }
                    }
                    .onAppear(perform: syncInternalTime)
                    .onChange(of: viewModel.selectedDayHour) { _, _ in
                        if !showingWakeTimePicker { syncInternalTime() }
                    }
                    .onChange(of: viewModel.selectedDayMinute) { _, _ in
                        if !showingWakeTimePicker { syncInternalTime() }
                    }
                    Spacer().frame(height: 40)
                    if viewModel.isAlarmEnabled && !showingWakeTimePicker {
                        Text("\("Next Up".localized(for: appLanguage)) · \(viewModel.nextUpcomingLabel)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 16)
                            .offset(y: daySelectorOffset)
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                    }
                    if !showingWakeTimePicker {
                        DayOfWeekSelector(scheduledWeekdays: viewModel.scheduledWeekdays, selectedWeekday: viewModel.selectedWeekday) { weekday in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.selectedWeekday = weekday
                            }
                        }
                        .allowsHitTesting(!showGuidedTour)
                        .tourTarget(.daySelector)
                        .padding(.top, viewModel.isAlarmEnabled ? 12 : 28)
                        .offset(y: daySelectorOffset)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                    }
                    Spacer().frame(height: 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Watch status panel — centered between the status pill and the day selector
                if viewModel.isAlarmEnabled && !showingWakeTimePicker && showingWatchDetails {
                    if let summary = watchSetupSummary {
                        GeometryReader { geo in
                            // The VStack layout is top-aligned with:
                            // 1. Spacer(60)
                            // 2. Clock block (280) with offset(-60) -> Visual bottom at 280
                            // 3. Spacer(40)
                            // 4. Day selector with offset(70) -> Visual top at 450
                            // We place the card in that ~170pt gap.
                            
                            // Center of gap is 365. We use 350 to push it slightly higher 
                            // toward the pill as requested.
                            let targetY: CGFloat = 350

                            watchSetupBanner(summary)
                                .padding(.horizontal, 24)
                                .frame(maxWidth: .infinity)
                                .position(x: geo.size.width / 2, y: targetY)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(true)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                    }
                }
                VStack {
                    Spacer()
                    if showingWakeTimePicker {
                        Button {
                            if hapticFeedbackEnabled { impactHaptic.impactOccurred() }
                            viewModel.updateWakeTime(hour: internalHour, minute: internalMinute)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                showingWakeTimePicker = false
                            }
                        } label: {
                            Text("Select".localized(for: appLanguage))
                                .font(.headline)
                                .padding(.horizontal, 48)
                        }
                        .buttonStyle(GlassButtonStyle(isProminent: true, tint: accent))
                        .padding(.bottom, alarmButtonBottomPadding)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    } else {
                        Button {
                            if hapticFeedbackEnabled { impactHaptic.impactOccurred() }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.toggleSelectedDay()
                            }
                        } label: {
                            Text((viewModel.isAlarmEnabledForSelectedDay ? "Alarm On" : "Alarm Off").localized(for: appLanguage))
                                .font(.headline)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isAlarmEnabledForSelectedDay)
                        }
                        .buttonStyle(GlassButtonStyle(isProminent: viewModel.isAlarmEnabledForSelectedDay, tint: accent))
                        .disabled(viewModel.isScheduling || showGuidedTour)
                        .tourTarget(.alarmButton)
                        .padding(.bottom, alarmButtonBottomPadding)
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .allowsHitTesting(!showGuidedTour)
            .toolbar {
                if !showingWakeTimePicker && !showGuidedTour && !isSettingsNavigationPending {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                isSettingsNavigationPending = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    isSettingsNavigationPending = false
                                    showingSettings = true
                                }
                            } label: {
                                Label("Settings".localized(for: appLanguage), systemImage: "gearshape")
                            }
                            Divider()
                            Button {
                                showingDiagnostics = true
                            } label: {
                                Label("Diagnostics".localized(for: appLanguage), systemImage: "ladybug")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.primary)
                                .font(.title2.weight(.medium))
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(showingWakeTimePicker ? "Set Wake Time".localized(for: appLanguage) : "Ninety".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingDiagnostics) {
                NavigationStack {
                    DiagnosticsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done".localized(for: appLanguage)) {
                                    showingDiagnostics = false
                                }
                            }
                        }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .overlay {
                if showGuidedTour {
                    ZStack {
                        Rectangle()
                            .fill(Color.black.opacity(0.001))
                            .contentShape(Rectangle())
                            .ignoresSafeArea()
                            .onTapGesture {}

                        GuidedTourView(isPresented: $showGuidedTour)
                            .transition(.opacity)
                    }
                }
            }
        }
    }


}
