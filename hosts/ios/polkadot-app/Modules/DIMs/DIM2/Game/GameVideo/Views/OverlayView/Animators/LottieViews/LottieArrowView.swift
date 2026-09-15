import UIKit
import Lottie

final class ScrubbableArrowView: UIView, ArrowStateRenderable {
    enum ArrowType {
        case leftGreen
        case rightRed

        var resourceName: String {
            switch self {
            case .leftGreen:
                "LeftGreenArrow"
            case .rightRed:
                "RightRedArrow"
            }
        }
    }

    private let animationView: LottieAnimationView

    let type: ArrowType

    var progress: CGFloat {
        get {
            animationView.currentProgress * 2
        }
        set {
            isProgressingForward = newValue >= progress
            let result = max(0, min(1, newValue)) / 2
            animationView.currentProgress = result
        }
    }

    var isProgressingForward: Bool = true

    init(type: ArrowType) {
        let config = LottieConfiguration()
        let animation = LottieAnimation.named(type.resourceName)
        animationView = LottieAnimationView(animation: animation, configuration: config)
        self.type = type

        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Handlers

    func animate(to progress: CGFloat, duration _: TimeInterval) {
        animationView.play(toProgress: progress)
    }

    // MARK: - Private Handlers

    private func setupViews() {
        isUserInteractionEnabled = false

        animationView.contentMode = .scaleAspectFill
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.animationSpeed = 6

        animationView.pause()

        addSubview(animationView)
        animationView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }
    }
}
