import UIKit
import DesignSystem

final class SensitiveContentOverlayView: UIView {
    let blurredBackgroundView: UIVisualEffectView = create {
        $0.effect = UIBlurEffect(style: .regular)
    }

    let imageView: UIImageView = create {
        $0.image = UIImage(resource: .sensitiveContent)
        $0.snp.makeConstraints {
            $0.width.height.equalTo(32)
        }
    }

    let titleLabel: Label = create {
        $0.typography = .bodyMedium
        $0.textColor = .fgSecondary
        $0.textAlignment = .center
        $0.numberOfLines = 0
        $0.text = "This content may be sensitive.\nTap to View and Judge"
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupViews() {
        clipsToBounds = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center

        stack.addArrangedSubview(imageView)
        stack.addArrangedSubview(titleLabel)

        addSubview(blurredBackgroundView)
        addSubview(stack)

        blurredBackgroundView.snp.makeConstraints {
            $0.directionalEdges.equalToSuperview()
        }

        stack.snp.makeConstraints {
            $0.center.equalToSuperview()
            $0.leading.greaterThanOrEqualToSuperview().priority(.low)
            $0.trailing.lessThanOrEqualToSuperview().priority(.low)
        }
    }
}
