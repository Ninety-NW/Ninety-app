import SwiftUI

struct ThemePreviewView: View {
    let theme: AppTheme
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    private var accent: Color { .themeAccent(for: colorScheme) }

    private var previewGradient: LinearGradient {
        switch theme {
        case .system:
            return LinearGradient(
                colors: [Color(white: 0.92), Color(white: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .light:
            return LinearGradient(
                colors: [Color(white: 0.97), Color(white: 0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .night:
            return LinearGradient(
                colors: [Color(white: 0.06), Color(red: 0.06, green: 0.14, blue: 0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(previewGradient)
                .frame(width: 96, height: 128)
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, accent)
                            .padding(8)
                    }
                }
                .overlay {
                    VStack(spacing: 10) {
                        Circle()
                            .fill(.white.opacity(theme == .night ? 0.18 : 0.65))
                            .frame(width: 32, height: 32)
                            .overlay {
                                Image(systemName: theme.icon)
                                    .foregroundStyle(theme == .night ? .white : .black.opacity(0.75))
                            }

                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white.opacity(theme == .night ? 0.16 : 0.55))
                            .frame(width: 56, height: 10)

                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white.opacity(theme == .night ? 0.10 : 0.38))
                            .frame(width: 42, height: 10)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            isSelected ? accent : Color.white.opacity(0.16),
                            lineWidth: isSelected ? 3 : 1
                        )
                }
                .shadow(color: .black.opacity(0.12), radius: 16, y: 10)

            Text(theme.rawValue)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .accessibilityLabel("\(theme.rawValue) theme\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    HStack(spacing: 32) {
        ThemePreviewView(theme: .light, isSelected: true)
        ThemePreviewView(theme: .night, isSelected: false)
        ThemePreviewView(theme: .system, isSelected: false)
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
