import SwiftUI

struct AlarmView: View {
    @ObservedObject var hapticManager = HapticWakeUpManager.shared
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.2, green: 0.02, blue: 0.06),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "alarm.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.orange)
                    .symbolEffect(.bounce, options: .repeating, value: hapticManager.isPlaying)
                
                Text("Wake Up!")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Button(action: {
                    WatchSensorManager.shared.stopActiveAlarmFromWatch()
                }) {
                    Text("STOP")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
    }
}

#Preview {
    AlarmView()
}
