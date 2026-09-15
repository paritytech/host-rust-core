import SwiftUI
import UIKit
import UIKit_iOS

final class DiagonalStripeBackgroundView: UIView {
    private let animationModel = DiagonalStripeAnimationModel()

    private lazy var hostingController = UIHostingController(
        rootView: DiagonalStripeView(model: animationModel)
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setIntroAnimationActive(_ isActive: Bool, replayKey: Int) {
        animationModel.setIntroAnimationActive(isActive, replayKey: replayKey)
    }

    func setShimmerActive(_ isActive: Bool) {
        animationModel.setShimmerActive(isActive)
    }

    func setupLayout() {
        backgroundColor = .clear
        isUserInteractionEnabled = false

        guard let hostedView = hostingController.view else {
            return
        }

        hostedView.backgroundColor = .clear
        hostedView.isUserInteractionEnabled = false

        addSubview(hostedView)
        hostedView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }
    }
}

@Observable
private final class DiagonalStripeAnimationModel {
    private(set) var mode = AnimationMode.idle

    enum AnimationMode: Equatable {
        case idle
        case intro(startDate: Date, replayKey: Int)
        case shimmer(startDate: Date)
    }

    func setIntroAnimationActive(_ isActive: Bool, replayKey: Int) {
        guard isActive else {
            if case .intro = mode {
                mode = .idle
            }
            return
        }

        if case let .intro(_, currentReplayKey) = mode,
           currentReplayKey == replayKey {
            return
        }

        mode = .intro(
            startDate: Date(),
            replayKey: replayKey
        )
    }

    func setShimmerActive(_ isActive: Bool) {
        guard isActive else {
            if case .shimmer = mode {
                mode = .idle
            }
            return
        }

        guard !isShimmerActive else {
            return
        }

        mode = .shimmer(startDate: Date())
    }

    var isShimmerActive: Bool {
        if case .shimmer = mode {
            return true
        }

        return false
    }
}

private struct DiagonalStripeView: View {
    var model: DiagonalStripeAnimationModel

    var body: some View {
        ZStack {
            if model.mode != .idle {
                TimelineView(.animation) { context in
                    DiagonalStripeBand(
                        state: bandState(for: context.date)
                    )
                }
            } else {
                DiagonalStripeBand(
                    state: .rest
                )
            }
        }
    }

    func bandState(for date: Date) -> DiagonalStripeBand.State {
        switch model.mode {
        case .idle:
            return .rest
        case let .intro(startDate, _):
            let linearProgress = date
                .timeIntervalSince(startDate)
                / Constants.introDurationSeconds

            return .make(
                phaseAProgress: Constants.introTimingCurve.value(
                    at: linearProgress.clamped(to: 0 ... 1)
                ),
                elapsedTime: max(
                    0,
                    date.timeIntervalSince(startDate) - Constants.introDurationSeconds
                )
            )
        case let .shimmer(startDate):
            return .make(
                phaseAProgress: 1,
                elapsedTime: 0,
                shimmerProgress: CGFloat(
                    date
                        .timeIntervalSince(startDate)
                        .normalizedLoop(period: Constants.shimmerDurationSeconds)
                )
            )
        }
    }

    enum Constants {
        static let introDurationSeconds: Double = 2
        static let shimmerDurationSeconds: Double = 3.2

        static let introTimingCurve = UnitCurve.bezier(
            startControlPoint: UnitPoint(x: 0, y: 0),
            endControlPoint: UnitPoint(x: 0.58, y: 1)
        )
    }
}

private struct DiagonalStripeBand: View {
    let state: State

    var gradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(uiColor: Constants.rest), location: 0),
                .init(color: Color(uiColor: state.gradientState.endColor), location: 1)
            ],
            startPoint: state.gradientState.startPoint,
            endPoint: state.gradientState.endPoint
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(gradient)

                if let shimmerProgress = state.shimmerProgress {
                    Rectangle()
                        .fill(shimmerGradient(progress: shimmerProgress))
                }
            }
            .frame(
                width: bandWidth(in: geometry.size),
                height: bandHeight(in: geometry.size)
            )
            .rotationEffect(.degrees(Constants.bandAngleDegrees))
            .position(
                x: geometry.size.width / 2,
                y: geometry.size.height * Constants.bandCenterYRatio
            )
        }
    }

    func bandWidth(in size: CGSize) -> CGFloat {
        hypot(size.width, size.height)
    }

    func bandHeight(in size: CGSize) -> CGFloat {
        size.height * Constants.bandHeightRatio
    }

    func shimmerGradient(progress: CGFloat) -> LinearGradient {
        let startX = Constants.shimmerStartPointXRange.interpolatedValue(
            at: progress.clamped(to: 0 ... 1)
        )

        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: Constants.shimmerCenter.opacity(0.4), location: 0.5),
                .init(color: .clear, location: 1)
            ],
            startPoint: UnitPoint(x: startX, y: 0),
            endPoint: UnitPoint(x: startX + Constants.shimmerWidthRatio, y: 0)
        )
    }
}

private extension DiagonalStripeBand {
    struct State {
        let gradientState: GradientState
        let shimmerProgress: CGFloat?

        static var rest: Self {
            make(phaseAProgress: 1, elapsedTime: 0)
        }

        static func make(
            phaseAProgress: Double,
            elapsedTime: TimeInterval,
            shimmerProgress: CGFloat? = nil
        ) -> Self {
            .init(
                gradientState: DiagonalStripeBand.makeGradientState(
                    phaseAProgress: phaseAProgress,
                    elapsedTime: elapsedTime
                ),
                shimmerProgress: shimmerProgress
            )
        }
    }

    enum Constants {
        static let dark = UIColor(resource: .dim2StripeDark)
        static let rest = UIColor(resource: .dim2StripeRest)
        static let pulseLow = UIColor(resource: .dim2StripePulseLow)
        static let shimmerCenter = Color(red: 0.62, green: 0.63, blue: 0.90)

        static let swayPeriodSeconds: Double = 10

        static let bandAngleDegrees: CGFloat = -47
        static let bandCenterYRatio: CGFloat = 0.6
        static let bandHeightRatio: CGFloat = 0.24

        static let gradientStartPointXRange: ClosedRange<CGFloat> = -0.25 ... 0
        static let gradientEndPointXRange: ClosedRange<CGFloat> = -0.125 ... 1
        static let gradientSwayAmplitude: CGFloat = 0.06
        static let shimmerStartPointXRange: ClosedRange<CGFloat> = -0.3 ... 1.37
        static let shimmerWidthRatio: CGFloat = 0.3
    }

    struct GradientState {
        let startPoint: UnitPoint
        let endPoint: UnitPoint
        let endColor: UIColor
    }

    struct PhaseAState {
        let progress: CGFloat
        let startPointX: CGFloat
        let endPointX: CGFloat
        let endColor: UIColor
    }

    struct PhaseBState {
        let swayOffset: CGFloat
        let pulseProgress: CGFloat
    }

    static func makeGradientState(
        phaseAProgress: Double,
        elapsedTime: TimeInterval
    ) -> GradientState {
        let phaseAState = makePhaseAState(progress: CGFloat(phaseAProgress))

        guard phaseAState.progress >= 1 else {
            return GradientState(
                startPoint: UnitPoint(x: phaseAState.startPointX, y: 0),
                endPoint: UnitPoint(x: phaseAState.endPointX, y: 0),
                endColor: phaseAState.endColor
            )
        }

        let phaseBState = makePhaseBState(elapsedTime: elapsedTime)

        return GradientState(
            startPoint: UnitPoint(
                x: phaseAState.startPointX - phaseBState.swayOffset,
                y: 0
            ),
            endPoint: UnitPoint(
                x: phaseAState.endPointX + phaseBState.swayOffset,
                y: 0
            ),
            endColor: Constants.rest.blended(
                to: Constants.pulseLow,
                progress: phaseBState.pulseProgress
            )
        )
    }

    static func makePhaseAState(progress: CGFloat) -> PhaseAState {
        let progress = progress.clamped(to: 0 ... 1)

        return PhaseAState(
            progress: progress,
            startPointX: Constants.gradientStartPointXRange.interpolatedValue(at: progress),
            endPointX: Constants.gradientEndPointXRange.interpolatedValue(at: progress),
            endColor: Constants.dark.blended(
                to: Constants.rest,
                progress: progress
            )
        )
    }

    static func makePhaseBState(elapsedTime: TimeInterval) -> PhaseBState {
        let phase = elapsedTime.normalizedLoop(period: Constants.swayPeriodSeconds)
        let angle = phase * .pi * 2

        return PhaseBState(
            swayOffset: CGFloat(sin(angle)) * Constants.gradientSwayAmplitude,
            pulseProgress: CGFloat((1 - cos(angle)) / 2)
        )
    }
}

private extension ClosedRange<CGFloat> {
    func interpolatedValue(at progress: CGFloat) -> CGFloat {
        lowerBound + (upperBound - lowerBound) * progress
    }
}

private extension TimeInterval {
    func normalizedLoop(period: TimeInterval) -> Double {
        truncatingRemainder(dividingBy: period) / period
    }
}
