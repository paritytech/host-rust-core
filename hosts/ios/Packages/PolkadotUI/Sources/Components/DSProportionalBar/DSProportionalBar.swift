import DesignSystem
import SwiftUI

/// A horizontal bar divided into proportional segments, clipped to a capsule and outlined.
///
/// Segments are laid out in order, each taking its `share` of the full width. Callers are
/// expected to pass shares that account for the whole bar; the last segment absorbs the
/// rounding remainder so the segments always meet the trailing edge exactly and no seam
/// appears there.
public struct DSProportionalBar: View {
    public struct Segment: Equatable {
        public enum Fill: Equatable {
            case solid(Color)
            /// Sliding diagonal stripes, for a segment representing work still in progress.
            case stripes(color: Color, background: Color)
        }

        public let share: Double
        public let fill: Fill

        public init(share: Double, fill: Fill) {
            self.share = share
            self.fill = fill
        }
    }

    /// Outline and clip shape of the bar as a whole.
    public enum CornerStyle: Equatable {
        case capsule
        /// Prefer this over ``capsule`` for a bar that can be about as wide as it is tall, where a
        /// capsule would round into a circle.
        case rounded(radius: CGFloat)
    }

    private let segments: [Segment]
    private let height: CGFloat
    private let cornerStyle: CornerStyle
    private let outlineColor: Color
    private let outlineWidth: CGFloat
    private let isAnimated: Bool

    public init(
        segments: [Segment],
        height: CGFloat,
        cornerStyle: CornerStyle = .capsule,
        outlineColor: Color,
        outlineWidth: CGFloat,
        isAnimated: Bool = true
    ) {
        self.segments = segments
        self.height = height
        self.cornerStyle = cornerStyle
        self.outlineColor = outlineColor
        self.outlineWidth = outlineWidth
        self.isAnimated = isAnimated
    }

    public var body: some View {
        GeometryReader { geometry in
            let widths = Self.widths(for: segments, totalWidth: geometry.size.width)

            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    Self.view(for: segment.fill, isAnimated: isAnimated)
                        .frame(width: widths[index])
                }

                Spacer(minLength: 0)
            }
            .frame(width: geometry.size.width, height: height)
            .clipShape(outline)
            .overlay(
                outline.stroke(outlineColor, lineWidth: outlineWidth)
            )
        }
        .frame(height: height)
    }
}

public extension DSProportionalBar {
    /// Widths in layout order, one per segment. The last entry takes whatever the rounded
    /// earlier entries left over, so the segments fill the bar exactly.
    static func widths(for segments: [Segment], totalWidth: CGFloat) -> [CGFloat] {
        let isEmpty = segments.allSatisfy { $0.share <= 0 }

        guard !isEmpty, totalWidth > 0, let last = segments.indices.last else {
            return Array(repeating: 0, count: segments.count)
        }

        var widths: [CGFloat] = segments.map { (CGFloat($0.share) * totalWidth).rounded() }
        widths[last] = max(totalWidth - widths.dropLast().reduce(0, +), 0)

        return widths
    }
}

private extension DSProportionalBar {
    var outline: AnyShape {
        switch cornerStyle {
        case .capsule:
            AnyShape(Capsule())
        case let .rounded(radius):
            AnyShape(RoundedRectangle(cornerRadius: radius))
        }
    }

    @ViewBuilder
    static func view(for fill: Segment.Fill, isAnimated: Bool) -> some View {
        switch fill {
        case let .solid(color):
            color
        case let .stripes(color, background):
            DSBarberPole(stripeColor: color, backgroundColor: background, isAnimated: isAnimated)
        }
    }
}

#if DEBUG
    #Preview("DSProportionalBar") {
        VStack(spacing: 16) {
            DSProportionalBar(
                segments: [
                    .init(share: 0.5, fill: .solid(.fgStaticWhite)),
                    .init(share: 0.2, fill: .stripes(color: .fgError, background: .fgStaticWhite)),
                    .init(share: 0.3, fill: .solid(.fgError))
                ],
                height: 20,
                outlineColor: .strokeTertiary,
                outlineWidth: 1
            )

            DSProportionalBar(
                segments: [
                    .init(share: 0.4, fill: .solid(.fgStaticWhite)),
                    .init(share: 0.6, fill: .stripes(color: .fgError, background: .fgStaticWhite))
                ],
                height: 21,
                cornerStyle: .rounded(radius: 5.5),
                outlineColor: .strokeTertiary,
                outlineWidth: 1
            )
            .frame(width: 21)
        }
        .padding()
        .background(Color.bgSurfaceContainer)
    }
#endif
