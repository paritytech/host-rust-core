import SwiftUI
import UIKit
import UIKit_iOS

struct TileFrameModel {
    let palette: Palette
    let strength: Strength

    enum Strength {
        case strong
        case soft
    }

    struct Palette {
        let bezelColors: [Color]
        let glowColor: Color

        init(
            bezelColors: [Color],
            glowColor: Color
        ) {
            self.bezelColors = bezelColors
            self.glowColor = glowColor
        }
    }
}

final class TileFrameView: UIView {
    private let modelStore: TileFrameModelStore

    private lazy var hostingController = UIHostingController(
        rootView: AnimatedTileFrame(modelStore: modelStore)
    )

    init(model: TileFrameModel, frame: CGRect = .zero) {
        modelStore = TileFrameModelStore(model: model)
        super.init(frame: frame)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
    }

    func bind(model: TileFrameModel) {
        modelStore.model = model
    }

    func setupLayout() {
        backgroundColor = .clear
        clipsToBounds = false
        isUserInteractionEnabled = false

        guard let hostedView = hostingController.view else {
            return
        }

        hostedView.backgroundColor = .clear
        hostedView.clipsToBounds = false
        hostedView.isUserInteractionEnabled = false

        addSubview(hostedView)
        hostedView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }
    }
}

@Observable
private final class TileFrameModelStore {
    var model: TileFrameModel

    init(model: TileFrameModel) {
        self.model = model
    }
}

private struct AnimatedTileFrame: View {
    let modelStore: TileFrameModelStore

    @State private var animationStartDate = Date()

    var body: some View {
        let model = modelStore.model

        TimelineView(.animation) { context in
            let animationState = AnimationState(
                date: context.date,
                startDate: animationStartDate,
                strength: model.strength
            )

            ZStack {
                glowStroke(model: model)
                    .blur(radius: model.strength.metrics.blur)
                    .offset(
                        x: animationState.offset.width,
                        y: animationState.offset.height
                    )
                    .opacity(animationState.glowOpacity)
                    .brightness(animationState.brightness)

                bezelStroke(model: model)
                    .brightness(animationState.brightness)

                movingLightStroke(rotationDegrees: animationState.lightRotationDegrees)
                    .blendMode(.screen)
            }
        }
        .onAppear {
            animationStartDate = Date()
        }
    }
}

private extension AnimatedTileFrame {
    func glowStroke(model: TileFrameModel) -> some View {
        RoundedRectangle(
            cornerRadius: Constants.cornerRadius,
            style: .continuous
        )
        .fill(model.palette.glowColor)
        .padding(-model.strength.metrics.glowSpread)
        .compositingGroup()
    }

    func bezelStroke(model: TileFrameModel) -> some View {
        RoundedRectangle(
            cornerRadius: Constants.cornerRadius,
            style: .continuous
        )
        .strokeBorder(bezelGradient(model: model), lineWidth: Constants.strokeWidth)
    }

    func movingLightStroke(rotationDegrees: Double) -> some View {
        RoundedRectangle(
            cornerRadius: Constants.cornerRadius,
            style: .continuous
        )
        .strokeBorder(
            movingLightGradient(rotationDegrees: rotationDegrees),
            lineWidth: Constants.strokeWidth
        )
    }

    func bezelGradient(model: TileFrameModel) -> LinearGradient {
        LinearGradient(
            colors: model.palette.bezelColors,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    func movingLightGradient(rotationDegrees: Double) -> AngularGradient {
        AngularGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(Constants.lightOpacity), location: 0.5),
                .init(color: .clear, location: 1)
            ],
            center: .center,
            startAngle: .degrees(Constants.lightStartAngleDegrees + rotationDegrees),
            endAngle: .degrees(Constants.lightEndAngleDegrees + rotationDegrees)
        )
    }

    struct AnimationState {
        let offset: CGSize
        let brightness: Double
        let glowOpacity: Double
        let lightRotationDegrees: Double

        init(date: Date, startDate: Date, strength: TileFrameModel.Strength) {
            let metrics = strength.metrics
            let elapsedTime = max(0, date.timeIntervalSince(startDate))
            let driftPhase = elapsedTime
                .truncatingRemainder(dividingBy: metrics.driftPeriodSeconds)
                / metrics.driftPeriodSeconds
            let lightSweepPhase = elapsedTime
                .truncatingRemainder(dividingBy: metrics.lightSweepPeriodSeconds)
                / metrics.lightSweepPeriodSeconds
            let angle: CGFloat = driftPhase * .pi * 2
            let breathePhase = elapsedTime
                .truncatingRemainder(dividingBy: metrics.breathePeriodSeconds)
                / metrics.breathePeriodSeconds
            let breatheProgress = (1 - cos(breathePhase * .pi * 2)) / 2

            offset = CGSize(
                width: cos(angle) * metrics.drift,
                height: sin(angle) * metrics.drift
            )
            brightness = breatheProgress * Constants.brightnessAmplitude
            glowOpacity = metrics.minimumGlowOpacity
                + breatheProgress * (metrics.maximumGlowOpacity - metrics.minimumGlowOpacity)
            lightRotationDegrees = lightSweepPhase * 360
        }
    }

    enum Constants {
        static let cornerRadius = CGFloat(16)
        static let strokeWidth = CGFloat(7)
        static let lightStartAngleDegrees = 140.0
        static let lightEndAngleDegrees = 270.0
        static let lightOpacity = 0.4
        static let brightnessAmplitude = 0.06
    }
}

private extension TileFrameModel.Strength {
    struct Metrics {
        let blur: CGFloat
        let glowSpread: CGFloat
        let drift: CGFloat
        let driftPeriodSeconds: TimeInterval
        let breathePeriodSeconds: TimeInterval
        let lightSweepPeriodSeconds: TimeInterval
        let minimumGlowOpacity: Double
        let maximumGlowOpacity: Double
    }

    var metrics: Metrics {
        switch self {
        case .strong:
            Metrics(
                blur: Constants.strongBlur,
                glowSpread: Constants.strongGlowSpread,
                drift: Constants.strongDrift,
                driftPeriodSeconds: Constants.strongDriftPeriodSeconds,
                breathePeriodSeconds: Constants.strongBreathePeriodSeconds,
                lightSweepPeriodSeconds: Constants.strongLightSweepPeriodSeconds,
                minimumGlowOpacity: Constants.strongMinimumGlowOpacity,
                maximumGlowOpacity: Constants.strongMaximumGlowOpacity
            )
        case .soft:
            Metrics(
                blur: Constants.softBlur,
                glowSpread: Constants.softGlowSpread,
                drift: Constants.softDrift,
                driftPeriodSeconds: Constants.softDriftPeriodSeconds,
                breathePeriodSeconds: Constants.softBreathePeriodSeconds,
                lightSweepPeriodSeconds: Constants.softLightSweepPeriodSeconds,
                minimumGlowOpacity: Constants.softMinimumGlowOpacity,
                maximumGlowOpacity: Constants.softMaximumGlowOpacity
            )
        }
    }

    enum Constants {
        static let strongBlur = CGFloat(28)
        static let strongGlowSpread = CGFloat(4)
        static let strongDrift = CGFloat(3)
        static let strongDriftPeriodSeconds = TimeInterval(2.2)
        static let strongBreathePeriodSeconds = TimeInterval(1.4)
        static let strongLightSweepPeriodSeconds = TimeInterval(1.4)
        static let strongMinimumGlowOpacity = 0.65
        static let strongMaximumGlowOpacity = 1.0

        static let softBlur = CGFloat(10)
        static let softGlowSpread = CGFloat(1)
        static let softDrift = CGFloat(2)
        static let softDriftPeriodSeconds = TimeInterval(9)
        static let softBreathePeriodSeconds = TimeInterval(5.4)
        static let softLightSweepPeriodSeconds = TimeInterval(3)
        static let softMinimumGlowOpacity = 0.55
        static let softMaximumGlowOpacity = 0.8
    }
}
