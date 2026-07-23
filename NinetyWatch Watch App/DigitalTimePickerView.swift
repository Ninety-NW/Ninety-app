import SwiftUI

// MARK: - Digital Time Picker
//
// Crown design:
//  • `.focusable()` + `.digitalCrownRotation` sono applicati
//    sull'intera VStack (non dentro un ZStack con bottoni).
//  • Range finito grande (0-10000) con reset al centro al cambio campo,
//    così l'utente non raggiunge mai i bordi reali.
//  • Accumulator frazionario: nessun micro-movimento viene perso.

struct DigitalTimePickerView: View {
    // hour: 0–11 (12h), displayed as 12 when 0
    @Binding var hour: Int
    @Binding var minute: Int
    @Binding var period: AlarmPeriod

    var onCancel: () -> Void
    var onSave:   () -> Void

    @State private var field: Field = .hour
    @State private var crown: Double = 5000       // starts at mid-range
    @State private var frac:  Double = 0          // sub-step accumulator
    @State private var isResettingCrown = false
    @FocusState private var focused: Bool

    private enum Field { case hour, minute }
    private static let crownMid: Double = 5000

    var body: some View {
        VStack(spacing: 10) {
            timeRow
            actionRow
        }
        .padding(.horizontal, 6)
        // ── Crown owned by the VStack (no nested focusable views) ────
        .focusable()
        .focused($focused)
        .digitalCrownRotation(
            $crown,
            from: 0, through: 10000, by: 1,
            sensitivity: .medium,
            isContinuous: false,      // bounded — user should never hit edges
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crown) { old, new in
            if isResettingCrown {
                isResettingCrown = false
                return
            }
            // Accumulate fractional steps to avoid losing sub-integer input
            frac += (new - old)
            let steps = Int(frac)
            guard steps != 0 else { return }
            frac -= Double(steps)
            switch field {
            case .hour:
                hour = ((hour + steps) % 12 + 12) % 12
            case .minute:
                minute = ((minute + steps) % 60 + 60) % 60
            }
        }
        .onAppear {
            if crown == Self.crownMid {
                isResettingCrown = false
            } else {
                isResettingCrown = true
                crown   = Self.crownMid
            }
            frac    = 0
            DispatchQueue.main.async {
                focused = true
            }
        }
        // Re-center crown and re-grab focus when switching fields
        .onChange(of: field) { _, _ in
            if crown == Self.crownMid {
                isResettingCrown = false
            } else {
                isResettingCrown = true
                crown   = Self.crownMid
            }
            frac    = 0
            focused = true
        }
    }

    // MARK: Time Row

    private var timeRow: some View {
        HStack(spacing: 3) {
            fieldBlock(
                text: String(format: "%02d", hour == 0 ? 12 : hour),
                active: field == .hour
            ) {
                field = .hour
            }

            Text(":")
                .font(.system(size: 24, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            fieldBlock(
                text: String(format: "%02d", minute),
                active: field == .minute
            ) {
                field = .minute
            }

            // AM / PM pill (plain button — does NOT take crown focus)
            Button { period.toggle() } label: {
                Text(period.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .frame(width: 34, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.1))
                    )
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
    }

    @ViewBuilder
    private func fieldBlock(text: String, active: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            Text(text)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 46, height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(active ? Color.green.opacity(0.18) : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            active ? Color.green : Color.white.opacity(0.12),
                            lineWidth: active ? 2 : 1
                        )
                )
                .foregroundStyle(active ? Color.white : Color.white.opacity(0.75))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .animation(.snappy(duration: 0.15), value: active)
    }

    // MARK: Action Row

    private var actionRow: some View {
        HStack(spacing: 12) {
            pill(icon: "xmark",      bg: Color.white.opacity(0.1),  fg: .white,  action: onCancel)
            pill(icon: "checkmark",  bg: Color.green,               fg: .black,  action: onSave)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func pill(icon: String, bg: Color, fg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(bg)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}
