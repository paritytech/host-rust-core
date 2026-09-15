import UIKit
import UIKit_iOS
import PolkadotUI
import DesignSystem

final class GameVideoRoundView: UIView {
    private let centerView: CenteringWrapperView<
        GenericPairValueView<ProgressView, Label>
    > = create {
        $0.spacerMultiplier = 1.2
        $0.minimumSpacerSize = 40

        $0.contentView.spacing = 40

        $0.contentView.sView.numberOfLines = 3
        $0.contentView.sView.textAlignment = .center
        $0.contentView.sView.typography = .headlineSmall
        $0.contentView.sView.textColor = .fgPrimary
    }

    private let progressLabel: Label = create {
        $0.numberOfLines = 2
        $0.textAlignment = .center
        $0.typography = .headlineLarge
        $0.textColor = .fgPrimary
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension GameVideoRoundView {
    func bind(viewModel: GameVideoViewLayout.ViewModel) {
        progressView.segmentCount = viewModel.subroundsCount

        switch viewModel.state {
        case .subroundStart:
            applySubroundStartState(viewModel: viewModel)
        case .waiting,
             .hostIntroduction,
             .hosting,
             .hostingEnd:
            break
        }
    }
}

private extension GameVideoRoundView {
    var progressView: ProgressView {
        centerView.contentView.fView
    }

    var descriptionLabel: UILabel {
        centerView.contentView.sView
    }

    func setupLayout() {
        addSubview(centerView)
        centerView.snp.makeConstraints {
            $0.width.equalTo(300)
            $0.centerX.equalToSuperview()
            $0.top.equalToSuperview()
            $0.bottom.equalToSuperview()
        }

        progressView.snp.makeConstraints {
            $0.height.equalTo(150)
        }

        addSubview(progressLabel)
        progressLabel.snp.makeConstraints {
            $0.bottom.equalTo(progressView.snp.bottom)
            $0.leading.equalTo(progressView.snp.leading).inset(16)
            $0.trailing.equalTo(progressView.snp.trailing).inset(16)
        }
    }

    func applySubroundStartState(viewModel: GameVideoViewLayout.ViewModel) {
        progressView.filledSegmentsCount = viewModel.currentSubroundCount
        progressLabel.text = String(
            localized: .Game.gameVideoProgressRoundNumber(
                String(viewModel.currentSubroundCount),
                String(viewModel.subroundsCount)
            )
        )
        descriptionLabel.text = viewModel.isOwnHosting
            ? String(localized: .Game.gameVideoRoundDescriptionHost)
            : String(localized: .Game.gameVideoRoundDescription)
    }
}

private extension GameVideoRoundView {
    final class ProgressView: UIView {
        var filledSegmentsCount = 0 {
            didSet {
                if oldValue != filledSegmentsCount {
                    setupColor()
                }
            }
        }

        var segmentCount = 12 {
            didSet {
                if oldValue != segmentCount {
                    setupSegments()
                }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            setupSegments()
        }
    }
}

private extension GameVideoRoundView.ProgressView {
    var filledColor: UIColor {
        .textAndIconsPrimaryDark
    }

    var emptyColor: UIColor {
        .textAndIconsTertiaryDark
    }

    var spacingDegrees: CGFloat {
        5.5
    }

    var lineWidth: CGFloat {
        12
    }

    func setupSegments() {
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }

        let totalArc: CGFloat = 180
        let spacing = spacingDegrees
        let totalSpacing = spacing * CGFloat(segmentCount - 1)
        let arcLength = totalArc - totalSpacing
        let anglePerSegment = arcLength / CGFloat(segmentCount)

        let radius = bounds.width / 2 - lineWidth / 2
        let center = CGPoint(x: bounds.midX, y: radius)

        for index in 0 ..< segmentCount {
            let startDeg = -90 - totalArc / 2 + CGFloat(index) * (anglePerSegment + spacing)
            let endDeg = startDeg + anglePerSegment

            let startAngle = startDeg * .pi / 180
            let endAngle = endDeg * .pi / 180

            let path = UIBezierPath(
                arcCenter: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: true
            )

            let segmentLayer = CAShapeLayer()
            segmentLayer.path = path.cgPath
            segmentLayer.fillColor = UIColor.clear.cgColor
            segmentLayer.lineWidth = lineWidth
            segmentLayer.lineCap = .round

            layer.addSublayer(segmentLayer)
        }

        setupColor()
    }

    func setupColor() {
        guard let sublayers = layer.sublayers else {
            return
        }
        for (index, layer) in sublayers.enumerated() {
            (layer as? CAShapeLayer)?.strokeColor = index < filledSegmentsCount
                ? filledColor.cgColor
                : emptyColor.cgColor
        }
    }
}
