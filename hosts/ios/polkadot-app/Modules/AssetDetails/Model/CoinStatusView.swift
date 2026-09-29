import Coinage
import DesignSystem
import SwiftUI

/// A coin's provenance: one circle per hop, oldest at the left, with inner dots for the
/// siblings the hop moved or produced alongside it.
///
/// A coin that has never hopped shows a single bar sized by its recycler's fungibility instead.
/// Where provenance runs out — an unknown recycler, or column left over past the last circle —
/// the stacked red-and-orange pair stands in for what is not known.
///
/// Hops that do not fit are counted into a chip rather than dropped silently.
struct CoinStatusView: View {
    struct Model: Equatable {
        /// One entry per hop, oldest first: the inner-dot count already resolved from the hop's
        /// `bundleSize` or `fanout`.
        let hopDots: [Int]
        /// Fungibility of the recycler the coin came out of. `nil` when it is not known.
        let fungibility: UInt8?
        /// Whether the current strategy leaves this coin spendable right now.
        let isSpendable: Bool
    }

    let model: Model

    var body: some View {
        Canvas { context, size in
            Self.draw(model, in: &context, size: size)
        }
        .frame(height: CoinageStatusMetrics.barHeight)
    }
}

extension CoinStatusView {
    /// How many circles are drawn, and how many hops the chip has to account for.
    struct CirclePlan: Equatable {
        let shown: Int
        let hidden: Int
        /// Zero when there is no chip — either nothing is hidden, or the column is too narrow to
        /// carry even the chip on its own. Callers draw a chip exactly when this is positive,
        /// which is what keeps a chip out of a column that cannot hold it.
        let chipWidth: CGFloat
        /// Width taken by the circles and, when there is one, the chip.
        let usedWidth: CGFloat
    }

    /// Fits as many whole circles as the column allows, giving up one more to the chip when some
    /// have to be hidden. A circle that would be clipped is never drawn part-way.
    ///
    /// `chipWidth` is passed in because measuring the chip's label needs a resolved graphics
    /// context, which the layout itself has no use for.
    static func plan(
        hopCount: Int,
        width: CGFloat,
        diameter: CGFloat,
        chipWidth: (Int) -> CGFloat
    ) -> CirclePlan {
        let spacing = CoinageStatusMetrics.itemSpacing

        func span(circles: Int) -> CGFloat {
            circles > 0 ? CGFloat(circles) * diameter + CGFloat(circles - 1) * spacing : 0
        }

        let fitting = max(min(Int((width + spacing) / (diameter + spacing)), hopCount), 0)

        if fitting == hopCount {
            return CirclePlan(
                shown: fitting,
                hidden: 0,
                chipWidth: 0,
                usedWidth: span(circles: fitting)
            )
        }

        for shown in stride(from: fitting, through: 0, by: -1) {
            let hidden = hopCount - shown
            let chip = chipWidth(hidden)
            let used = shown > 0 ? span(circles: shown) + spacing + chip : chip

            if used <= width {
                return CirclePlan(shown: shown, hidden: hidden, chipWidth: chip, usedWidth: used)
            }
        }

        // Too narrow for even the chip. The hops are still unaccounted for, but there is nowhere
        // to say so, so the row falls through to the unknown pair alone.
        return CirclePlan(shown: 0, hidden: hopCount, chipWidth: 0, usedWidth: 0)
    }
}

private extension CoinStatusView {
    static func draw(_ model: Model, in context: inout GraphicsContext, size: CGSize) {
        guard !model.hopDots.isEmpty else {
            drawUnhopped(model, in: &context, size: size)
            return
        }

        let plan = plan(
            hopCount: model.hopDots.count,
            width: size.width,
            diameter: size.height,
            chipWidth: { overflowChipWidth(count: $0, in: context) }
        )

        drawCircles(Array(model.hopDots.prefix(plan.shown)), in: &context, height: size.height)

        if plan.chipWidth > 0 {
            drawOverflowChip(
                count: plan.hidden,
                in: &context,
                rect: CGRect(
                    x: plan.usedWidth - plan.chipWidth,
                    y: 0,
                    width: plan.chipWidth,
                    height: size.height
                )
            )
        }

        let origin = plan.usedWidth + CoinageStatusMetrics.itemSpacing
        let remaining = size.width - origin

        guard remaining >= CoinageStatusMetrics.minimumVisibleWidth else { return }

        drawUnknown(
            in: &context,
            rect: CGRect(x: origin, y: 0, width: remaining, height: size.height)
        )
    }

    static func drawUnhopped(_ model: Model, in context: inout GraphicsContext, size: CGSize) {
        guard let fungibility = model.fungibility else {
            drawUnknown(in: &context, rect: CGRect(origin: .zero, size: size))
            return
        }

        // A perfectly fungible recycler scores a zero-length bar; the minimum keeps a mark.
        let width = max(
            CoinageStatusMetrics.fraction(forScore: fungibility) * size.width,
            CoinageStatusMetrics.minimumBarWidth
        )
        let inset = CoinageStatusMetrics.outlineWidth / 2
        let rect = CGRect(
            x: inset,
            y: inset,
            width: max(width - CoinageStatusMetrics.outlineWidth, 0),
            height: size.height - CoinageStatusMetrics.outlineWidth
        )
        let path = Path(
            roundedRect: rect,
            cornerRadius: CoinageStatusMetrics.solidBarCornerRadius
        )

        context.fill(path, with: .color(model.isSpendable ? Color.fgStaticWhite : Color.fgError))
        context.stroke(
            path,
            with: .color(CoinageStatusMetrics.markFrame),
            lineWidth: CoinageStatusMetrics.markFrameWidth
        )
    }

    static func drawCircles(_ hopDots: [Int], in context: inout GraphicsContext, height: CGFloat) {
        let spacing = CoinageStatusMetrics.itemSpacing

        for (index, dots) in hopDots.enumerated() {
            let rect = CGRect(
                x: CGFloat(index) * (height + spacing),
                y: 0,
                width: height,
                height: height
            )
            drawCircle(dots: dots, in: &context, rect: rect)
        }
    }

    /// One hop: a solid red disc carrying its dot count.
    ///
    /// No darker interior. Any red dark enough to read as a distinct fill behind the ring also
    /// reads as black on a light surface — the last attempt sat at luminance 0.066, level with
    /// the theme's own body text. The design has no such fill either: its rows are solid discs,
    /// and the one dark-centred circle in the file is a legend drawn on a black canvas.
    static func drawCircle(dots: Int, in context: inout GraphicsContext, rect: CGRect) {
        context.fill(Path(ellipseIn: rect), with: .color(Color.fgError))

        let centre = CGPoint(x: rect.midX, y: rect.midY)

        for offset in CoinageStatusMetrics.innerDotOffsets(forDots: dots) {
            fillDot(
                at: CGPoint(x: centre.x + offset.x, y: centre.y + offset.y),
                in: &context
            )
        }
    }

    /// White, as the design has it: 5.4:1 on the red disc, on every theme.
    static func fillDot(at centre: CGPoint, in context: inout GraphicsContext) {
        let size = CoinageStatusMetrics.innerDotSize
        let rect = CGRect(
            x: centre.x - size / 2,
            y: centre.y - size / 2,
            width: size,
            height: size
        )

        context.fill(
            Path(roundedRect: rect, cornerRadius: CoinageStatusMetrics.innerDotCornerRadius),
            with: .color(Color.fgStaticWhite)
        )
    }

    /// Theme tokens, not pinned colours: unlike the marks, the chip carries no status, and the
    /// ground it sits on is the theme's own background — which is exactly what these are paired
    /// with by construction.
    static func overflowLabel(count: Int) -> Text {
        Text(verbatim: "+" + count.formatted())
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Color.fgSecondary)
    }

    static func overflowChipWidth(count: Int, in context: GraphicsContext) -> CGFloat {
        let measured = context
            .resolve(overflowLabel(count: count))
            .measure(in: CGSize(width: 200, height: 200))

        return max(
            CoinageStatusMetrics.overflowChipMinimumWidth,
            measured.width + CoinageStatusMetrics.overflowChipPadding * 2
        )
    }

    /// Outlined rather than filled, so it reads as a count of what is missing instead of as one
    /// more hop.
    static func drawOverflowChip(count: Int, in context: inout GraphicsContext, rect: CGRect) {
        let inset = CoinageStatusMetrics.outlineWidth / 2
        let capsule = Path(
            roundedRect: rect.insetBy(dx: inset, dy: inset),
            cornerRadius: rect.height / 2
        )

        context.stroke(
            capsule,
            with: .color(Color.strokeTertiary),
            lineWidth: CoinageStatusMetrics.outlineWidth
        )
        context.draw(
            overflowLabel(count: count),
            at: CGPoint(x: rect.midX, y: rect.midY),
            anchor: .center
        )
    }

    /// Fills a bar of the stacked pair and frames it. Orange measures under 2:1 against a light
    /// ground, so the frame is what makes these two legible rather than their own contrast.
    static func frame(_ path: Path, _ color: Color, in context: inout GraphicsContext) {
        context.fill(path, with: .color(color))
        context.stroke(
            path,
            with: .color(CoinageStatusMetrics.markFrame),
            lineWidth: CoinageStatusMetrics.thinFrameWidth
        )
    }

    /// The stacked pair standing in for provenance that is not known. Thinner than a solid bar
    /// and centred in the row, so it reads as an absence rather than as a measurement.
    static func drawUnknown(in context: inout GraphicsContext, rect: CGRect) {
        let height = CoinageStatusMetrics.unknownBarHeight
        let total = height * 2 + CoinageStatusMetrics.stackSpacing
        let top = rect.minY + (rect.height - total) / 2

        let topBar = CGRect(x: rect.minX, y: top, width: rect.width, height: height)
        let bottomBar = CGRect(x: rect.minX, y: top + total - height, width: rect.width, height: height)

        frame(Path(roundedRect: topBar, cornerRadius: height / 2), Color.fgError, in: &context)
        frame(
            Path(roundedRect: bottomBar, cornerRadius: height / 2),
            Color.bgStatusWarning,
            in: &context
        )
    }
}

extension CoinStatusView {
    /// One provenance circle on its own, for the legend. Shares ``drawCircle`` with the rows, so
    /// the explanation cannot illustrate a mark the list does not draw.
    struct CircleIllustration: View {
        let dots: Int

        var body: some View {
            Canvas { context, size in
                CoinStatusView.drawCircle(
                    dots: dots,
                    in: &context,
                    rect: CGRect(origin: .zero, size: size)
                )
            }
            .frame(
                width: CoinageStatusMetrics.barHeight,
                height: CoinageStatusMetrics.barHeight
            )
        }
    }

    /// The unknown pair on its own, for the legend.
    struct UnknownIllustration: View {
        var body: some View {
            Canvas { context, size in
                CoinStatusView.drawUnknown(
                    in: &context,
                    rect: CGRect(origin: .zero, size: size)
                )
            }
            .frame(height: CoinageStatusMetrics.barHeight)
        }
    }
}
