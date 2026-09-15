import SwiftUI
import UIKit
import DesignSystem
import Coinage

// Presentation pieces for `PaymentPrivacyModeCard`: the layout constants, the lit sphere, the pointer, the
// stepped scale, and the accent-derived shading. Split from the card so each stays a small, focused unit.

// MARK: - Layout constants

enum PrivacyModeMetrics {
    static let circle: CGFloat = 28
    static let selectedCircle: CGFloat = 40
    static let trackHeight: CGFloat = 40
    static let glowBlur: CGFloat = 12
    static let iconFraction: CGFloat = 0.42
    static let tickWidth: CGFloat = 2
    static let tickHeight: CGFloat = 6
    static let tickStep: CGFloat = 8
    static let marker: CGFloat = 8
    static let selectedMarker: CGFloat = 12
    static let markerGlowBlur: CGFloat = 8

    /// Mid-drag cross-fade bounds: a slow drag has room for a gentle dissolve, a flick must not leave the
    /// outgoing glyph hanging behind the finger. `fastDragSpeed` is the mode-widths-per-second at which the
    /// fade reaches its shortest.
    static let slowDragFade: Double = 0.28
    static let fastDragFade: Double = 0.14
    static let fastDragSpeed: CGFloat = 3

    /// How much of the recess shadow a fully lit floor removes; a dark floor keeps nearly all of it.
    static let lightSurfaceFalloff: CGFloat = 0.8

    /// Half the selected sphere, so the outer modes' centres sit that far from the track edges and the
    /// spheres rest fully inside — matching the design's ~20pt leading/trailing offsets.
    static var inset: CGFloat { selectedCircle / 2 }

    /// Tall enough for the selected sphere plus the glow spreading either side of it.
    static var boxHeight: CGFloat { selectedCircle + glowBlur * 2 }
}

// MARK: - Mode circle

/// One mode as a lit sphere on the track: a vertical accent gradient with a gradient rim, a drop shadow,
/// and — only once a mode is settled on — an accent glow. Selecting grows the sphere; dragging keeps it
/// grown but unlit. A dragged sphere adopts each mode as it passes the midpoint towards it, so `mode`
/// changes under it mid-gesture: the glyph is then cross-faded and the accent blended rather than swapped
/// in a single frame.
struct ModeCircleView: View {
    let mode: RecyclingStrategyType
    let isSelected: Bool
    let hasGlow: Bool
    var fadeDuration: Double = 0.2

    /// The mode being faded away from, held until the fade completes; `fadeProgress` runs 0 → 1 across it.
    @State private var previousMode: RecyclingStrategyType
    @State private var currentMode: RecyclingStrategyType
    @State private var fadeProgress: CGFloat

    init(mode: RecyclingStrategyType, isSelected: Bool, hasGlow: Bool, fadeDuration: Double = 0.2) {
        self.mode = mode
        self.isSelected = isSelected
        self.hasGlow = hasGlow
        self.fadeDuration = fadeDuration
        _previousMode = State(initialValue: mode)
        _currentMode = State(initialValue: mode)
        _fadeProgress = State(initialValue: 1)
    }

    var body: some View {
        let diameter = isSelected ? PrivacyModeMetrics.selectedCircle : PrivacyModeMetrics.circle
        let accent = previousMode.displayAccentColor
            .blended(with: currentMode.displayAccentColor, fraction: fadeProgress)

        ZStack {
            Circle()
                .fill(accent)
                .frame(width: diameter, height: diameter)
                .blur(radius: PrivacyModeMetrics.glowBlur)
                .opacity(hasGlow ? 0.45 : 0)

            Circle()
                .fill(currentMode.circleGradient(accent: accent, selected: isSelected))
                .overlay(Circle().strokeBorder(currentMode.circleBorderGradient(accent: accent), lineWidth: 1))
                .frame(width: diameter, height: diameter)
                .shadow(color: .shadowMedium.opacity(0.7), radius: 4, y: 4)
                .overlay(glyphs(diameter: diameter))
        }
        .frame(width: PrivacyModeMetrics.boxHeight, height: PrivacyModeMetrics.boxHeight)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .animation(.easeInOut(duration: 0.2), value: hasGlow)
        .onChange(of: mode) { _, newMode in
            guard newMode != currentMode else { return }
            previousMode = currentMode
            currentMode = newMode
            fadeProgress = 0
            // Linear on purpose: an eased cross-fade loses ink in the middle of the exchange and reads
            // as a blink.
            withAnimation(.linear(duration: fadeDuration)) { fadeProgress = 1 }
        }
    }

    /// Outgoing and incoming glyphs dissolving into each other on the same fade.
    @ViewBuilder
    private func glyphs(diameter: CGFloat) -> some View {
        let font = Font.system(size: diameter * PrivacyModeMetrics.iconFraction, weight: .semibold)
        ZStack {
            Image(systemName: previousMode.displayIconName)
                .font(font)
                .foregroundStyle(.fgStaticWhite)
                .opacity(1 - fadeProgress)

            Image(systemName: currentMode.displayIconName)
                .font(font)
                .foregroundStyle(.fgStaticWhite)
                .opacity(fadeProgress)
        }
    }
}

// MARK: - Mode marker

/// The pointer under a mode, tying its sphere to its label. The selected one is larger and glows in the
/// mode's own accent.
struct ModeMarkerView: View {
    let mode: RecyclingStrategyType
    let isSelected: Bool

    var body: some View {
        let side = isSelected ? PrivacyModeMetrics.selectedMarker : PrivacyModeMetrics.marker
        let color = isSelected ? mode.displayAccentColor : mode.markerMutedColor

        Triangle()
            .fill(color)
            .frame(width: side, height: side)
            .background(
                Triangle()
                    .fill(mode.displayAccentColor)
                    .frame(width: side, height: side)
                    .blur(radius: PrivacyModeMetrics.markerGlowBlur)
                    .opacity(isSelected ? 0.45 : 0)
            )
            .frame(height: PrivacyModeMetrics.selectedMarker)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - Tick scale

/// The stepped speed-to-privacy scale cut into the groove: upright bars coloured by a horizontal gradient
/// across the mode accents, spanning centre-to-centre of the outer modes.
struct TickScale: View {
    let start: CGFloat
    let end: CGFloat

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let top = size.height / 2 - PrivacyModeMetrics.tickHeight / 2
            var tickX = start
            while tickX + PrivacyModeMetrics.tickWidth <= end {
                path.addRect(CGRect(
                    x: tickX,
                    y: top,
                    width: PrivacyModeMetrics.tickWidth,
                    height: PrivacyModeMetrics.tickHeight
                ))
                tickX += PrivacyModeMetrics.tickStep
            }
            context.fill(
                path,
                with: .linearGradient(
                    Gradient(colors: [.fgWarning, .fgSuccess, .avatarBgSapphire, .avatarBgAmethyst]),
                    startPoint: CGPoint(x: start, y: 0),
                    endPoint: CGPoint(x: end, y: 0)
                )
            )
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Mode appearance

/// Per-mode shades derived from the mode's flat accent token rather than hardcoded, so the lit sphere stays
/// self-consistent: the fill is a vertical gradient, tinted towards static white at the top when selected
/// and shaded towards onyx below; the rim and muted marker share the same derivation.
private extension RecyclingStrategyType {
    func circleGradient(accent: Color, selected: Bool) -> LinearGradient {
        let top = selected
            ? accent.blended(with: .fgStaticWhite, fraction: 0.1)
            : accent.blended(with: .avatarBgOnyx, fraction: 0.25)
        let bottom = selected
            ? accent.blended(with: .avatarBgOnyx, fraction: 0.35)
            : accent.blended(with: .avatarBgOnyx, fraction: 0.55)
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    func circleBorderGradient(accent: Color) -> LinearGradient {
        LinearGradient(
            colors: [
                accent.blended(with: .fgStaticWhite, fraction: 0.4),
                accent.blended(with: .avatarBgOnyx, fraction: 0.55)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var markerMutedColor: Color {
        displayAccentColor.blended(with: .avatarBgOnyx, fraction: 0.45)
    }
}

// MARK: - Colour blending

extension Color {
    /// Linear RGBA blend towards `other`. The privacy card's shades are derived from a single accent token,
    /// which needs mixing the design system does not expose. Kept **dynamic**: both inputs are re-resolved
    /// against the render-time traits, so the blend follows the active design-system theme (the `appTheme`
    /// trait each token reads) instead of being frozen to one appearance.
    func blended(with other: Color, fraction: CGFloat) -> Color {
        let clamped = min(max(fraction, 0), 1)
        let base = UIColor(self)
        let target = UIColor(other)

        return Color(uiColor: UIColor { traits in
            let resolvedBase = base.resolvedColor(with: traits)
            let resolvedTarget = target.resolvedColor(with: traits)

            var baseRed: CGFloat = 0, baseGreen: CGFloat = 0, baseBlue: CGFloat = 0, baseAlpha: CGFloat = 0
            var tintRed: CGFloat = 0, tintGreen: CGFloat = 0, tintBlue: CGFloat = 0, tintAlpha: CGFloat = 0
            resolvedBase.getRed(&baseRed, green: &baseGreen, blue: &baseBlue, alpha: &baseAlpha)
            resolvedTarget.getRed(&tintRed, green: &tintGreen, blue: &tintBlue, alpha: &tintAlpha)

            return UIColor(
                red: baseRed + (tintRed - baseRed) * clamped,
                green: baseGreen + (tintGreen - baseGreen) * clamped,
                blue: baseBlue + (tintBlue - baseBlue) * clamped,
                alpha: baseAlpha + (tintAlpha - baseAlpha) * clamped
            )
        })
    }
}
