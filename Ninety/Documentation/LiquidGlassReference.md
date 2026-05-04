# iOS 26 Liquid Glass: Comprehensive Swift/SwiftUI Reference

https://conor.fyi/writing/liquid-glass-reference

## Overview

![Screenshot 2025-11-16 at 14 50 09 Medium](https://github.com/user-attachments/assets/7355a936-ccda-48d5-8c13-5039dfc490b2)

iOS 26 Liquid Glass represents Apple's most significant design evolution since iOS 7, introduced at WWDC 2025 (June 9, 2025). **Liquid Glass is a translucent, dynamic material that reflects and refracts surrounding content while transforming to bring focus to user tasks**. This unified design language spans iOS 26, iPadOS 26, macOS Tahoe 26, watchOS 26, tvOS 26, and visionOS 26.

Liquid Glass features real-time light bending (lensing), specular highlights responding to device motion, adaptive shadows, and interactive behaviors. The material continuously adapts to background content, light conditions, and user interactions, creating depth and hierarchy between foreground controls and background content.

**Key Characteristics:**
- **Lensing**: Bends and concentrates light in real-time (vs. traditional blur that scatters light)
- **Materialization**: Elements appear by gradually modulating light bending
- **Fluidity**: Gel-like flexibility with instant touch responsiveness
- **Morphing**: Dynamic transformation between control states
- **Adaptivity**: Multi-layer composition adjusting to content, color scheme, and size

---

## Part 1: Foundation & Basics

### 1.1 Core Concepts

**Design Philosophy**
Liquid Glass is exclusively for the **navigation layer** that floats above app content. Never apply to content itself (lists, tables, media). This maintains clear visual hierarchy: content remains primary while controls provide functional overlay.

**Material Variants**

| Variant | Use Case | Transparency | Adaptivity |
|---------|----------|--------------|------------|
| `.regular` | Default for most UI | Medium | Full - adapts to any content |
| `.clear` | Media-rich backgrounds | High | Limited - requires dimming layer |
| `.identity` | Conditional disable | None | N/A - no effect applied |

**Basic Implementation**
```swift
.glassEffect()  // Default: .regular variant, .capsule shape
.glassEffect(.regular, in: .capsule, isEnabled: true)
```

**Glass Type Modifiers**
```swift
.glassEffect(.regular.tint(.blue))
.glassEffect(.regular.interactive()) // iOS only: scaling, shimmer, touch-point illumination
```

### 1.2 Interactive Modifier Behaviors
- Scaling on press
- Bouncing animation
- Shimmering effect
- Touch-point illumination that radiates to nearby glass
- Response to tap and drag gestures

---

## Part 2: Intermediate Techniques

### 2.1 GlassEffectContainer
- Combines multiple Liquid Glass shapes into unified composition.
- Improves rendering performance by sharing sampling region.
- Enables morphing transitions between glass elements.
- **Critical Rule**: Glass cannot sample other glass; container provides shared sampling region.

```swift
GlassEffectContainer(spacing: 40.0) {
    // Glass elements within 40 points will morph together
    ForEach(icons) { icon in
        IconView(icon)
            .glassEffect()
    }
}
```

### 2.2 Morphing Transitions with glassEffectID
Requires:
1. Elements in same `GlassEffectContainer`
2. Each view has `glassEffectID` with shared namespace
3. Animation applied to state changes

```swift
.glassEffectID("toggle", in: namespace)
```

### 2.3 Glass Button Styles
- `.glass`: Translucent, see-through (Secondary actions)
- `.glassProminent`: Opaque, no background show-through (Primary actions)

---

## Part 3: Advanced Implementation

### 3.1 glassEffectUnion
Manually combine distant glass effects to merge.
```swift
.glassEffectUnion(id: "tools", namespace: controls)
```

### 3.2 Performance Optimization
1. **Always Use GlassEffectContainer** for multiple elements.
2. **Conditional Glass with .identity** to avoid layout recalculation.
3. **Limit Continuous Animations**.
4. **Test on Older Devices** (iPhone 11-13).

---

## Part 4: Platform & Compatibility

### 4.1 Backward Compatibility
```swift
if #available(iOS 26.0, *) {
    self.glassEffect(.regular)
} else {
    // Fallback (e.g., .ultraThinMaterial)
}
```

### 4.2 Known Issues (Beta)
- `.glassProminent` with `.circle` has rendering artifacts. Workaround: apply `.clipShape(Circle())`.
- Widget backgrounds may show black in Standard/Dark modes.
