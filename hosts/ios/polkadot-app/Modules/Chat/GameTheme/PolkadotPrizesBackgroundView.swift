import UIKit
import SnapKit

final class PolkadotPrizesBackgroundView: UIView {
    private let gradientLayer = CAGradientLayer()
    private let patternView = UIImageView()

    init() {
        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    private func setupViews() {
        isUserInteractionEnabled = false

        gradientLayer.colors = [
            PolkadotPrizesPalette.gradientTop.cgColor,
            PolkadotPrizesPalette.gradientBottom.cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(gradientLayer)

        patternView.image = UIImage(resource: .polkadotPrizesPattern)
        patternView.contentMode = .scaleAspectFill
        patternView.clipsToBounds = true
        patternView.alpha = PolkadotPrizesPalette.patternOpacity
        addSubview(patternView)
        patternView.snp.makeConstraints { $0.edges.equalToSuperview() }
    }
}
