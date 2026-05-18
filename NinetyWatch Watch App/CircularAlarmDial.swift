import SwiftUI

struct CircularAlarmDial: View {
    @Binding var hour: Int
    @Binding var minute: Int

    @State var crownStep: Double = 0

    let totalSteps = 24 * 12

    var totalMinutes: Int {
        ((hour % 24) * 60) + minute
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = side / 2
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let markerRadius = radius - 12
            let angle = Angle.degrees((Double(totalMinutes) / 1440.0 * 360.0) - 90.0)
            let marker = CGPoint(
                x: center.x + cos(angle.radians) * markerRadius,
                y: center.y + sin(angle.radians) * markerRadius
            )

            ZStack {
                Circle()
                    .stroke(.white.opacity(0.16), lineWidth: 2)
                    .frame(width: side - 8, height: side - 8)
                    .position(center)

                ForEach(0..<60, id: \.self) { tick in
                    let isHour = tick % 5 == 0
                    Capsule()
                        .fill(isHour ? Color.white.opacity(0.62) : Color.white.opacity(0.22))
                        .frame(width: isHour ? 2 : 1, height: isHour ? 10 : 5)
                        .offset(y: -(radius - 20))
                        .rotationEffect(.degrees(Double(tick) * 6))
                        .position(center)
                }

                ForEach(Array(stride(from: 0, through: 21, by: 3)), id: \.self) { labelHour in
                    let labelAngle = Angle.degrees((Double(labelHour) / 24.0 * 360.0) - 90.0)
                    let labelRadius = radius - 38
                    Text("\(labelHour)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.58))
                        .position(
                            x: center.x + cos(labelAngle.radians) * labelRadius,
                            y: center.y + sin(labelAngle.radians) * labelRadius
                        )
                }

                Circle()
                    .fill(Color.green)
                    .frame(width: 15, height: 15)
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.85), lineWidth: 1.2)
                    }
                    .shadow(color: .green.opacity(0.6), radius: 6)
                    .position(marker)

                Text(String(format: "%02d:%02d", hour, minute))
                    .font(.system(size: 33, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
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
            crownStep = Double(totalMinutes / 5)
        }
        .onChange(of: hour) {
            crownStep = Double(totalMinutes / 5)
        }
        .onChange(of: minute) {
            crownStep = Double(totalMinutes / 5)
        }
        .onChange(of: crownStep) { _, newValue in
            let normalized = ((Int(round(newValue)) % totalSteps) + totalSteps) % totalSteps
            let minutesOfDay = normalized * 5
            let newHour = minutesOfDay / 60
            let newMinute = minutesOfDay % 60
            guard newHour != hour || newMinute != minute else { return }
            hour = newHour
            minute = newMinute
        }
    }
}
