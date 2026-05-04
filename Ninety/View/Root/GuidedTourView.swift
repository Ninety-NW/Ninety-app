//
//  GuidedTourView.swift
//  Ninety
//
//  Compact spotlight-based onboarding tour.
//  Frames captured via .onGeometryChange in .global space.
//

import SwiftUI

// MARK: - Shared Frame Store

class TourFrameStore: ObservableObject {
    @Published var clockPillFrame: CGRect   = .zero
    @Published var daySelectorFrame: CGRect = .zero
    @Published var alarmButtonFrame: CGRect = .zero
}

// MARK: - Tour Step

private enum TourStep: Int, CaseIterable {
    case welcome = 0, timePicker, daySelector, alarmToggle, privacy, ready

    var icon: String {
        switch self {
        case .welcome:     return "brain.head.profile.fill"
        case .timePicker:  return "clock.fill"
        case .daySelector: return "calendar"
        case .alarmToggle: return "bell.badge.fill"
        case .privacy:     return "lock.shield.fill"
        case .ready:       return "sparkles"
        }
    }

    var title: String {
        switch self {
        case .welcome:     return "Welcome to Ninety"
        case .timePicker:  return "Set Your Wake Time"
        case .daySelector: return "Customize Every Day"
        case .alarmToggle: return "On or Off. Your Call."
        case .privacy:     return "Private by Design"
        case .ready:       return "You're All Set"
        }
    }

    var body: String {
        switch self {
        case .welcome:
            return "Ninety uses on-device machine learning to find the ideal moment to wake you — within the time you set."
        case .timePicker:
            return "Tap the clock to choose when you need to be up. Ninety wakes you at the best point in your sleep cycle."
        case .daySelector:
            return "Each day can have its own wake-up time. Tap a day to select it and adjust the schedule."
        case .alarmToggle:
            return "Toggle the alarm for each day independently — keep your weekdays and weekends perfectly balanced."
        case .privacy:
            return "Your sleep data never leaves your device. No servers, no cloud — everything runs locally on your iPhone."
        case .ready:
            return "Everything is set up. Sweet dreams."
        }
    }

    var isFullScreen: Bool {
        switch self { case .welcome, .privacy, .ready: return true; default: return false }
    }
}

// MARK: - Guided Tour View

struct GuidedTourView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var frameStore: TourFrameStore
    @AppStorage("appLanguage") private var appLanguage: String = AppLanguage.english.rawValue
    @AppStorage("hapticFeedbackEnabled") private var hapticFeedbackEnabled: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    @State private var step: TourStep = .welcome
    @State private var show: Bool = false
    @State private var cardScale: CGFloat = 0.92
    @State private var iconAngle: Double = 0

    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private var accent: Color { .themeAccent(for: colorScheme) }

    // Spotlight padding around the element
    private let pad: CGFloat = 12
    // Estimated card height for vertical placement math
    private let estCardH: CGFloat = 220
    // Reserved bottom space for the fixed navigation row.
    private let bottomBarClearance: CGFloat = 24

    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    fileprivate init(isPresented: Binding<Bool>, initialStep: TourStep) {
        self._isPresented = isPresented
        self._step = State(initialValue: initialStep)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Full-screen tap blocker so controls underneath the tour
                // never receive touches while onboarding is visible.
                // Background opacity
                Rectangle()
                    .fill(Color.black.opacity(0.001))
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {}



                group(in: proxy)
                    .allowsHitTesting(false)
            }
            .opacity(show ? 1 : 0)
            .highPriorityGesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        if value.translation.width < -30 {
                            if step == .ready { close() } else { go(back: false) }
                        } else if value.translation.width > 30 {
                            if step.rawValue > 0 { go(back: true) }
                        }
                    }
            )
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { show = true; cardScale = 1 }
        }
    }

    @ViewBuilder
    private func group(in proxy: GeometryProxy) -> some View {
        spotCard(in: proxy)
    }



    // MARK: - Spotlight card

    private func spotCard(in proxy: GeometryProxy) -> some View {
        // Convert global target frame to this overlay's local coordinate space.
        let overlayGlobal = proxy.frame(in: .global)
        let actualSpotFrame = step.isFullScreen
            ? CGRect(x: proxy.size.width / 2 + overlayGlobal.minX, y: proxy.size.height / 2 + overlayGlobal.minY, width: 0, height: 0)
            : spotFrame
        let localRaw = actualSpotFrame.offsetBy(dx: -overlayGlobal.minX, dy: -overlayGlobal.minY)
        let hFrame = step.isFullScreen ? localRaw : localRaw.insetBy(dx: -pad, dy: -pad)

        return ZStack {
            // Dimmed mask with cutout
            SpotlightShape(cutout: hFrame, radius: step.isFullScreen ? 0 : spotR + pad)
                .fill(style: FillStyle(eoFill: true))
                .foregroundStyle(Color.black.opacity(0.5))
                .ignoresSafeArea()

            // Accent ring
            RoundedRectangle(cornerRadius: step.isFullScreen ? 0 : spotR + pad, style: .continuous)
                .strokeBorder(accent, lineWidth: 2)
                .frame(width: hFrame.width, height: hFrame.height)
                .shadow(color: accent.opacity(0.45), radius: 10)
                .position(x: hFrame.midX, y: hFrame.midY)
                .opacity(step.isFullScreen ? 0 : 1)

            // Tooltip card
            VStack(spacing: 0) {
                Spacer()
                VStack(alignment: .leading, spacing: 16) {
                    ZStack(alignment: .leading) {
                        Image(systemName: step.icon)
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(accent)
                            .symbolRenderingMode(.hierarchical)

                        Text(step.title.localized(for: appLanguage))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 48)
                    }

                    Text(step.body.localized(for: appLanguage))
                        .font(.system(size: 17, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .lineSpacing(3)
                        .lineLimit(4)

                    HStack {
                        Spacer()
                        dots
                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(width: min(proxy.size.width - 48, 320))
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
                .scaleEffect(cardScale)
                Spacer()
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Helpers

    private var spotFrame: CGRect {
        switch step {
        case .timePicker:  return frameStore.clockPillFrame
        case .daySelector: return frameStore.daySelectorFrame
        case .alarmToggle: return frameStore.alarmButtonFrame
        default:           return .zero
        }
    }

    private var spotR: CGFloat {
        switch step {
        case .timePicker:  return 38
        case .daySelector: return 20
        default:           return 24
        }
    }

    private var spotlightCardYOffset: CGFloat {
        switch step {
        case .alarmToggle: return -56
        default:           return 0
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(TourStep.allCases, id: \.rawValue) { s in
                Circle()
                    .fill(s == step ? accent : Color.primary.opacity(0.2))
                    .frame(width: s == step ? 8 : 5, height: s == step ? 8 : 5)
            }
        }
    }



    private func go(back: Bool) {
        if hapticFeedbackEnabled { haptic.impactOccurred() }
        let n = back ? step.rawValue - 1 : step.rawValue + 1
        guard let target = TourStep(rawValue: n) else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { cardScale = 0.9 }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75).delay(0.12)) {
            step = target; iconAngle = 0; cardScale = 1
        }
        withAnimation(.easeInOut(duration: 0.55).delay(0.3)) { iconAngle = 360 }
    }

    private func close() {
        if hapticFeedbackEnabled { haptic.impactOccurred() }
        withAnimation(.easeIn(duration: 0.22)) { show = false; cardScale = 0.94 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { isPresented = false }
    }
}

// MARK: - Spotlight cutout shape

private struct SpotlightShape: Shape {
    let cutout: CGRect
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRect(rect)
        p.addPath(Path(roundedRect: cutout, cornerRadius: radius, style: .continuous))
        return p
    }
}

// MARK: - TourTargetModifier

enum TourTargetRole { case clockPill, daySelector, alarmButton }

struct TourTargetModifier: ViewModifier {
    let role: TourTargetRole
    @EnvironmentObject private var store: TourFrameStore

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { geo in
                geo.frame(in: .global)
            } action: { frame in
                switch role {
                case .clockPill:    store.clockPillFrame   = frame
                case .daySelector:  store.daySelectorFrame = frame
                case .alarmButton:  store.alarmButtonFrame = frame
                }
            }
    }
}

extension View {
    func tourTarget(_ role: TourTargetRole) -> some View {
        modifier(TourTargetModifier(role: role))
    }
}

// MARK: - Clamp helper

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}

private struct GuidedTourPreviewHost: View {
    @State private var isPresented = true
    @StateObject private var frameStore = TourFrameStore()

    let step: TourStep

    var body: some View {
        ZStack {
            HorizonBackground(isActive: true)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 286, height: 96)

                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 260, height: 54)

                Spacer()

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 180, height: 58)
            }
            .padding(.top, 160)
            .padding(.bottom, 48)

            if isPresented {
                GuidedTourView(isPresented: $isPresented, initialStep: step)
                    .environmentObject(frameStore)
            }
        }
        .onAppear {
            frameStore.clockPillFrame = CGRect(x: 54, y: 188, width: 286, height: 96)
            frameStore.daySelectorFrame = CGRect(x: 67, y: 325, width: 260, height: 54)
            frameStore.alarmButtonFrame = CGRect(x: 107, y: 686, width: 180, height: 58)
        }
    }
}

#Preview("Guided Tour Welcome") {
    GuidedTourPreviewHost(step: .welcome)
}

#Preview("Guided Tour Time Picker") {
    GuidedTourPreviewHost(step: .timePicker)
}

#Preview("Guided Tour Alarm") {
    GuidedTourPreviewHost(step: .alarmToggle)
}
