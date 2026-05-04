import SwiftUI

// MARK: - Theme-aware accent color

extension Color {
    /// Returns `.orange` in light mode, `.blue` in dark mode — matching the settings theme preview.
    static func themeAccent(for colorScheme: ColorScheme) -> Color {
        colorScheme == .light ? .orange : .blue
    }

    /// Softer schedule-specific accent tones used in the alarm screen.
    static func scheduleAccent(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .light {
            return Color(red: 0.96, green: 0.67, blue: 0.30)
        } else {
            return Color(red: 0.17, green: 0.36, blue: 0.68)
        }
    }
}

struct HorizonBackground: View {
    @Environment(\.colorScheme) var colorScheme
    var isActive: Bool = true
    var accentOverride: Color? = nil
    
    private var accent: Color { accentOverride ?? .themeAccent(for: colorScheme) }
    
    var body: some View {
        ZStack {
            (colorScheme == .light ? Color(white: 0.95) : Color.black)
                .ignoresSafeArea()
            
            // Subtle top gradient
            LinearGradient(
                colors: colorScheme == .light ?
                    [Color(white: 0.95), Color(white: 0.9)] :
                    [.black, Color(white: 0.05)],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            VStack {
                Spacer()
                
                // Keep the original placement, but separate glow and stroke so the arc stays sharp.
                ZStack {
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: isActive
                                ? [
                                    accent.opacity(colorScheme == .light ? 0.22 : 0.30),
                                    accent.opacity(colorScheme == .light ? 0.12 : 0.18),
                                    accent.opacity(0.02),
                                    .clear
                                ]
                                : [
                                    Color.gray.opacity(colorScheme == .light ? 0.08 : 0.14),
                                    Color.gray.opacity(colorScheme == .light ? 0.04 : 0.08),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 24,
                                endRadius: 300
                            )
                        )
                        .frame(width: 660, height: 360)
                        .scaleEffect(x: 1.0, y: 0.82)
                        .offset(y: 198)
                        .blur(radius: 22)
                        .animation(.easeInOut(duration: 1.0), value: isActive)

                    Ellipse()
                        .stroke(
                            isActive
                            ? accent.opacity(colorScheme == .light ? 0.18 : 0.28)
                            : Color.gray.opacity(colorScheme == .light ? 0.06 : 0.12),
                            lineWidth: 22
                        )
                        .frame(width: 528, height: 270)
                        .blur(radius: 18)
                        .offset(y: 125)
                        .animation(.easeInOut(duration: 1.0), value: isActive)

                    Ellipse()
                        .stroke(
                            LinearGradient(
                                colors: isActive
                                ? [
                                    accent.opacity(0.10),
                                    accent.opacity(colorScheme == .light ? 0.72 : 0.88),
                                    accent.opacity(0.10)
                                ]
                                : [
                                    Color.gray.opacity(0.05),
                                    Color.gray.opacity(colorScheme == .light ? 0.22 : 0.32),
                                    Color.gray.opacity(0.05)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 500, height: 250)
                        .overlay {
                            Ellipse()
                                .stroke(
                                    Color.white.opacity(colorScheme == .light ? 0.28 : 0.08),
                                    lineWidth: 0.8
                                )
                        }
                        .offset(y: 125)
                        .transition(.opacity)
                }
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.8), value: isActive)
        }
    }
}

#Preview {
    HorizonBackground()
}
