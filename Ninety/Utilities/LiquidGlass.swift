import SwiftUI

// MARK: - Liquid Glass Types

public enum GlassVariant {
    case regular
    case clear
    case identity
}

public struct Glass {
    public static var regular: Glass { Glass(variant: .regular) }
    public static var clear: Glass { Glass(variant: .clear) }
    public static var identity: Glass { Glass(variant: .identity) }
    
    var variant: GlassVariant
    var tintColor: Color?
    var isInteractive: Bool = false
    
    public func tint(_ color: Color) -> Glass {
        var copy = self
        copy.tintColor = color
        return copy
    }
    
    public func interactive() -> Glass {
        var copy = self
        copy.isInteractive = true
        return copy
    }
}

// MARK: - Modifiers

public extension View {
    @ViewBuilder
    func glassEffect<S: Shape>(
        _ glass: Glass = .regular,
        in shape: S = Capsule(), // Default shape as per spec
        isEnabled: Bool = true
    ) -> some View {
        if isEnabled && glass.variant != .identity {
            self.modifier(LiquidGlassModifier(glass: glass, shape: shape))
        } else {
            self
        }
    }
    
    func glassEffectID<ID: Hashable>(
        _ id: ID,
        in namespace: Namespace.ID
    ) -> some View {
        self.matchedGeometryEffect(id: id, in: namespace)
    }
}

// MARK: - Button Styles

public struct GlassButtonStyle: ButtonStyle {
    var isProminent: Bool
    var tint: Color?
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isProminent ? .white : .primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background {
                if isProminent {
                    Capsule()
                        .fill(tint ?? .blue)
                        .glassEffect(.regular.interactive())
                } else {
                    Capsule()
                        .glassEffect(.regular.interactive())
                }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == GlassButtonStyle {
    static var glass: Self { GlassButtonStyle(isProminent: false) }
    static var glassProminent: Self { GlassButtonStyle(isProminent: true) }
}

// MARK: - Container

public struct GlassEffectContainer<Content: View>: View {
    var spacing: CGFloat?
    let content: Content
    
    public init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content()
    }
    
    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content()
    }
    
    public var body: some View {
        // In a real implementation, this provides a shared sampling region.
        // Here we just wrap the content.
        content
    }
}

// MARK: - Implementation Details

struct LiquidGlassModifier<S: Shape>: ViewModifier {
    let glass: Glass
    let shape: S
    
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // Lensing effect (approx with Material + subtle distortion in real implementation)
                    Group {
                        if glass.variant == .clear {
                            shape.fill(.clear)
                        } else {
                            shape.fill(.ultraThinMaterial)
                        }
                    }
                    .environment(\.colorScheme, colorScheme) // Ensure material matches theme
                    
                    if let tint = glass.tintColor {
                        shape
                            .fill(tint.opacity(0.15))
                    }
                    
                    // Specular Highlight
                    shape
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.4), .clear, .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.1), radius: 10, y: 5)
            }
            // Interactive behaviors
            .compositingGroup() // Ensure effects apply to the whole stack
    }
}
