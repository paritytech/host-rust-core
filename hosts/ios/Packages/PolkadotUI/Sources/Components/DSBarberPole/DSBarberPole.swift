import DesignSystem
import SwiftUI

/// Diagonal stripes sliding leftwards, for depicting work that is still in progress.
///
/// The pattern repeats every `stripeWidth * 2`, so sliding by exactly one period and snapping back
/// is seamless. Only a static layer is offset, which keeps the animation off the main thread even
/// with many of these on screen at once.
///
/// Two things have to hold for the wrap to be invisible, and both are about coverage rather than
/// timing: the drawn pattern must extend past the layer's own bounds — a leaning stripe's far
/// corner is clipped, so drawing only to the edge leaves a wedge of bare background — and the
/// layer must be wide enough to still cover the viewport after a full period of travel.
public struct DSBarberPole: View {
    private let stripeWidth: CGFloat
    private let slant: CGFloat
    private let periodDuration: Double
    private let stripeColor: Color
    private let backgroundColor: Color

    @State private var isSliding = false

    /// - Parameter slant: Horizontal run per unit of height — the stripes' lean.
    public init(
        stripeWidth: CGFloat = 5,
        slant: CGFloat = 0.7,
        periodDuration: Double = 0.6,
        stripeColor: Color = .fgError,
        backgroundColor: Color = .fgStaticWhite
    ) {
        self.stripeWidth = stripeWidth
        self.slant = slant
        self.periodDuration = periodDuration
        self.stripeColor = stripeColor
        self.backgroundColor = backgroundColor
    }

    public var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let period = Self.period(forStripeWidth: stripeWidth)
            let margin = period + size.height * slant

            ZStack(alignment: .leading) {
                backgroundColor

                Canvas { context, canvasSize in
                    Self.drawStripes(
                        in: &context,
                        size: canvasSize,
                        stripeWidth: stripeWidth,
                        slant: slant,
                        color: stripeColor
                    )
                }
                .frame(width: size.width + margin * 2, height: size.height)
                .offset(x: isSliding ? -margin - period : -margin)
                .animation(
                    .linear(duration: periodDuration).repeatForever(autoreverses: false),
                    value: isSliding
                )
            }
            // Leading, not the default centre: the stripe layer is deliberately wider than the
            // frame, and centring it would shift it half its overdraw before the offset below
            // even applies — which starves the right edge partway through each slide.
            .frame(width: size.width, height: size.height, alignment: .leading)
            .clipped()
            .onAppear { isSliding = true }
        }
    }
}

private extension DSBarberPole {
    static func period(forStripeWidth stripeWidth: CGFloat) -> CGFloat {
        stripeWidth * 2
    }

    /// Fills the canvas with stripes, starting and ending a full stripe-and-lean beyond its
    /// bounds. The clip then removes only overshoot, so every point inside is patterned — no
    /// wedge is left where a leaning stripe crosses an edge.
    ///
    /// The pattern's phase is anchored to the canvas, not to the animation, so offsetting the
    /// whole canvas by one period reproduces an identical pattern.
    static func drawStripes(
        in context: inout GraphicsContext,
        size: CGSize,
        stripeWidth: CGFloat,
        slant: CGFloat,
        color: Color
    ) {
        let period = period(forStripeWidth: stripeWidth)
        let lean = size.height * slant
        let overshoot = lean + period

        var origin = -overshoot

        while origin < size.width + overshoot {
            context.fill(
                stripe(at: origin, height: size.height, stripeWidth: stripeWidth, lean: lean),
                with: .color(color)
            )
            origin += period
        }
    }

    static func stripe(
        at origin: CGFloat,
        height: CGFloat,
        stripeWidth: CGFloat,
        lean: CGFloat
    ) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: origin, y: height))
        path.addLine(to: CGPoint(x: origin + lean, y: 0))
        path.addLine(to: CGPoint(x: origin + lean + stripeWidth, y: 0))
        path.addLine(to: CGPoint(x: origin + stripeWidth, y: height))
        path.closeSubpath()

        return path
    }
}

#if DEBUG
    #Preview("DSBarberPole") {
        VStack(spacing: 16) {
            DSBarberPole()
                .frame(width: 200, height: 20)
                .clipShape(Capsule())

            DSBarberPole(stripeWidth: 10, slant: 0, periodDuration: 1.2)
                .frame(width: 200, height: 20)
                .clipShape(Capsule())
        }
        .padding()
        .background(Color.bgSurfaceContainer)
    }
#endif
