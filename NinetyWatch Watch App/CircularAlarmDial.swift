import SwiftUI

struct CircularAlarmDial: View {
    @Binding var hour: Int
    @Binding var minute: Int
    @Binding var period: AlarmPeriod

    @State var crownStep: Double = 0

    let totalSteps = 12 * 12

    var displayHour: Int {
        ((hour % 12) + 12) % 12
    }

    var displayHourText: Int {
        displayHour == 0 ? 12 : displayHour
    }

    var dialMinutes: Int {
        (displayHour * 60) + minute
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = side / 2
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let segmentRadius = radius - 7
            let windowStartMinutes = dialMinutes - 30
            let windowStartAngle = Angle.degrees((Double(windowStartMinutes) / 720.0 * 360.0) - 90.0)
            let angle = Angle.degrees((Double(dialMinutes) / 720.0 * 360.0) - 90.0)
            let segmentStart = CGPoint(
                x: center.x + cos(windowStartAngle.radians) * segmentRadius,
                y: center.y + sin(windowStartAngle.radians) * segmentRadius
            )
            let segmentHead = CGPoint(
                x: center.x + cos(angle.radians) * segmentRadius,
                y: center.y + sin(angle.radians) * segmentRadius
            )

            ZStack {
                Circle()
                    .stroke(.white.opacity(0.16), lineWidth: 2)
                    .frame(width: side - 1, height: side - 1)
                    .position(center)

                ForEach(0..<60, id: \.self) { tick in
                    let isHour = tick % 5 == 0
                    Capsule()
                        .fill(isHour ? Color.white.opacity(0.62) : Color.white.opacity(0.22))
                        .frame(width: isHour ? 2 : 1, height: isHour ? 8 : 4)
                        .offset(y: -(radius - 7))
                        .rotationEffect(.degrees(Double(tick) * 6))
                        .position(center)
                }

                ForEach(0..<12, id: \.self) { labelHour in
                    let labelAngle = Angle.degrees((Double(labelHour) / 12.0 * 360.0) - 90.0)
                    let labelRadius = radius - 24
                    Text(labelHour == 0 ? "12" : "\(labelHour)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.58))
                        .position(
                            x: center.x + cos(labelAngle.radians) * labelRadius,
                            y: center.y + sin(labelAngle.radians) * labelRadius
                        )
                }

                Path { path in
                    path.addArc(
                        center: center,
                        radius: segmentRadius,
                        startAngle: windowStartAngle,
                        endAngle: angle,
                        clockwise: false
                    )
                }
                .stroke(
                    Color.green.opacity(0.62),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )

                Circle()
                    .fill(Color.green.opacity(0.7))
                    .frame(width: 5, height: 5)
                    .position(segmentStart)

                Circle()
                    .fill(Color.green)
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.85), lineWidth: 1)
                    }
                    .shadow(color: .green.opacity(0.65), radius: 4)
                    .position(segmentHead)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(String(format: "%02d:%02d", displayHourText, minute))
                        .font(.system(size: 29, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Button {
                        period.toggle()
                    } label: {
                        Text(period.title)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .frame(width: 29, height: 18)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(period == .am ? .white.opacity(0.9) : .black)
                    .background {
                        Capsule()
                            .fill(period == .am ? Color.white.opacity(0.12) : Color.yellow)
                            .overlay {
                                Capsule()
                                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.7)
                            }
                    }
                }
                    .position(center)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .focusable(true)
        .digitalCrownRotation(
            $crownStep,
            from: 0,
            through: Double(totalSteps - 1),
            by: 1,
            sensitivity: .low,
            isContinuous: true,
            isHapticFeedbackEnabled: true
        )
        .onAppear {
            normalizeToTwelveHourDial()
            crownStep = Double(dialMinutes / 5)
        }
        .onChange(of: hour) {
            crownStep = Double(dialMinutes / 5)
        }
        .onChange(of: minute) {
            crownStep = Double(dialMinutes / 5)
        }
        .onChange(of: crownStep) { _, newValue in
            let normalized = ((Int(round(newValue)) % totalSteps) + totalSteps) % totalSteps
            let minutesInDial = normalized * 5
            let newHour = minutesInDial / 60
            let newMinute = minutesInDial % 60
            guard newHour != hour || newMinute != minute else { return }
            hour = newHour
            minute = newMinute
        }
    }

    func normalizeToTwelveHourDial() {
        let normalizedHour = displayHour
        let normalizedMinute = max(0, min(55, (minute / 5) * 5))
        if hour != normalizedHour {
            hour = normalizedHour
        }
        if minute != normalizedMinute {
            minute = normalizedMinute
        }
    }
}
