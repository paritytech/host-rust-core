import UIKit
import UIKit_iOS
import PolkadotUI
import DesignSystem

final class GameVideoPlayerBannedOverlayView: UIView {
    private let iconView: UIImageView = create {
        $0.contentMode = .scaleAspectFit
        $0.image = .gameVideoBanned
        $0.tintColor = .textAndIconsPrimaryDark
    }

    private let label: PolkadotUI.Label = create {
        $0.typography = .paragraphSmall
        $0.textColor = .textAndIconsSecondary
        $0.textAlignment = .center
        $0.text = String(localized: .Game.gameVideoBannedPlayer)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .backgroundTertiary
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private extension GameVideoPlayerBannedOverlayView {
    func setupLayout() {
        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8

        iconView.snp.makeConstraints {
            $0.width.height.equalTo(32)
        }

        addSubview(stack)
        stack.snp.makeConstraints {
            $0.center.equalToSuperview()
            $0.leading.greaterThanOrEqualToSuperview().inset(4)
            $0.trailing.lessThanOrEqualToSuperview().inset(4)
            $0.top.greaterThanOrEqualToSuperview().inset(4)
            $0.bottom.lessThanOrEqualToSuperview().inset(4)
        }
    }
}
