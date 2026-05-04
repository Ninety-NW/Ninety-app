import SwiftUI

struct TestModeView: View {
    @AppStorage("appLanguage") private var appLanguage: String = AppLanguage.english.rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color { .themeAccent(for: colorScheme) }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 20) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WATCH MODEL ONLY")
                            .font(.caption.bold())
                            .tracking(1)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)

                        VStack(alignment: .leading, spacing: 12) {
                            Label("The old iPhone model test runner is disabled.", systemImage: "iphone.slash")
                                .font(.headline)
                                .foregroundStyle(accent)

                            Text("Smart wake decisions now run on Apple Watch. iPhone diagnostics show Watch epoch summaries, but the phone no longer loads a sleep-stage model or classifies raw sensor payloads.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity)
        }
        .background {
            HorizonBackground(isActive: false)
                .ignoresSafeArea()
        }
        .navigationTitle("Test Mode")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .containerBackground(.clear, for: .navigation)
    }
}

#Preview {
    NavigationStack {
        TestModeView()
    }
}
