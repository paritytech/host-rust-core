import UIKit
import UIKit_iOS
import PolkadotUI

final class GameVideoWaitingCountdownView: UIView {
    private let titleLabel: UILabel = {
        let view = UILabel()
        view.font = .titleMulish32ExtraBlack()
        view.textColor = .white100
        view.textAlignment = .center
        view.numberOfLines = 0
        view.text = String(localized: .Game.gameVideoWaitingCountdownTitle)
        return view
    }()

    private let countdownLabel: UILabel = {
        let view = UILabel()
        view.font = .titleMulish164ExtraBlack()
        view.textAlignment = .center
        view.numberOfLines = 1
        view.adjustsFontSizeToFitWidth = true
        view.minimumScaleFactor = 0.5
        return view
    }()

    private lazy var stackView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [titleLabel, countdownLabel])
        view.axis = .vertical
        view.alignment = .center
        view.spacing = 8
        return view
    }()

    private var lastAnimatedSecond: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func bind(viewModel: GameVideoViewLayout.ViewModel.WaitingCountdown) {
        countdownLabel.text = viewModel.text
        countdownLabel.textColor = digitColor(for: viewModel.secondsRemaining)

        updateHeartbeat(for: viewModel.secondsRemaining)
    }
}

private extension GameVideoWaitingCountdownView {
    func setupLayout() {
        addSubview(stackView)
        stackView.snp.makeConstraints {
            $0.center.equalToSuperview()
            $0.leading.greaterThanOrEqualToSuperview().offset(8)
            $0.trailing.lessThanOrEqualToSuperview().offset(-8)
        }

        countdownLabel.snp.makeConstraints {
            $0.width.lessThanOrEqualToSuperview()
        }
    }

    func digitColor(for seconds: Int) -> UIColor {
        seconds <= 10 ? .yellowBadge : .textAndIconsPrimaryDark
    }

    func updateHeartbeat(for seconds: Int) {
        guard seconds <= 5 else {
            lastAnimatedSecond = nil
            countdownLabel.layer.removeAllAnimations()
            countdownLabel.transform = .identity
            return
        }

        guard lastAnimatedSecond != seconds else {
            return
        }

        lastAnimatedSecond = seconds
        animateHeartbeat()
    }

    func animateHeartbeat() {
        countdownLabel.layer.removeAllAnimations()
        countdownLabel.transform = .identity

        UIView.animateKeyframes(
            withDuration: 0.72,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.18) {
                    self.countdownLabel.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
                }

                UIView.addKeyframe(withRelativeStartTime: 0.18, relativeDuration: 0.2) {
                    self.countdownLabel.transform = .identity
                }

                UIView.addKeyframe(withRelativeStartTime: 0.48, relativeDuration: 0.16) {
                    self.countdownLabel.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
                }

                UIView.addKeyframe(withRelativeStartTime: 0.64, relativeDuration: 0.22) {
                    self.countdownLabel.transform = .identity
                }
            },
            completion: { [weak countdownLabel] _ in
                countdownLabel?.transform = .identity
            }
        )
    }
}
