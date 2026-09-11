import SwiftUI
import DesignSystem

/// Per-chain status indicator. The arc length carries health (block age, finality stall, and ping
/// combined worst-of) and is colored by health score; the centre icon identifies the chain and is
/// tinted by connection state, inverting against the disc once a fully healthy ring fills in.
struct ChainStatusRingView: View, Hashable {
    let viewModel: ChainConnectionStatusViewModel

    /// Stroke and dot scale with this, so the two hosts stay visually the same mark at
    /// different sizes — the strip is bound by its 20pt band, the panel is not.
    var diameter: CGFloat = 16

    var body: some View {
        let health = viewModel.health
        let arcColor = ChainStatusRingStyle.arcColor(for: health)
        let isFilled = ChainStatusRingStyle.isFilled(for: health)

        ZStack {
            Circle()
                .fill(arcColor)
                .opacity(isFilled ? 1 : 0)
                .animation(healthAnimation, value: health)

            Circle()
                .stroke(Color.fgPrimary.opacity(0.2), lineWidth: lineWidth)

            Circle()
                .trim(from: 1 - health, to: 1)
                .stroke(
                    arcColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(healthAnimation, value: health)

            ChainStatusIconView(
                icon: viewModel.icon,
                color: isFilled ? .bgSurfaceMain : dotColor,
                diameter: dotDiameter,
                isPulsing: viewModel.state == .connecting
            )
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        // A plain interpolated Text("...") would be treated as a localizable format string and
        // register a "%@, %@" entry in the package catalog; verbatim avoids localization.
        .accessibilityLabel(Text(verbatim: "\(viewModel.title), \(viewModel.stateTitle)"))
    }
}

private extension ChainStatusRingView {
    var healthAnimation: Animation { .easeOut(duration: 0.3) }

    var lineWidth: CGFloat { diameter / 8 }

    var dotDiameter: CGFloat { diameter * 0.625 }

    var dotColor: Color {
        switch viewModel.state {
        case .connected:
            .fgPrimary
        case .connecting:
            .fgTertiary
        case .offline:
            .bgStatusError
        }
    }
}

/// Owns the repeating animation's `@State` so `ChainStatusRingView` keeps the synthesized
/// `Hashable` conformance that content reuse depends on.
private struct ChainStatusIconView: View {
    let icon: ChainStatusIcon
    let color: Color
    let diameter: CGFloat
    let isPulsing: Bool

    @State private var isDimmed = false

    var body: some View {
        Image(icon.imageResource)
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .frame(width: diameter, height: diameter)
            .opacity(isDimmed ? 0.3 : 1)
            .animation(pulseAnimation, value: isDimmed)
            .onAppear { isDimmed = isPulsing }
            .onChange(of: isPulsing) { _, newValue in isDimmed = newValue }
    }

    private var pulseAnimation: Animation {
        isPulsing
            ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
            : .easeInOut(duration: 0.2)
    }
}

private extension ChainStatusIcon {
    var imageResource: ImageResource {
        switch self {
        case .people:
            .statusIconPeople
        case .bulletin:
            .statusIconBulletin
        case .assetHub:
            .statusIconAssethub
        case .statementStore:
            .statusIconSstore
        }
    }
}
