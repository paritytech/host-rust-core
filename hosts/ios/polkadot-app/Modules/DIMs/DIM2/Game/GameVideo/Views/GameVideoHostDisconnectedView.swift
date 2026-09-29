import UIKit
import UIKit_iOS
import PolkadotUI
import DesignSystem

final class GameVideoHostDisconnectedView: UIView {
    let contentView: GenericPairValueView<UIImageView, PolkadotUI.Label> = .create { view in
        view.makeVertical()
        view.stackView.alignment = .center

        view.sView.numberOfLines = 6
        view.sView.typography = .headlineSmall
        view.sView.textColor = .textAndIconsPrimaryDark
        view.sView.textAlignment = .center
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

extension GameVideoHostDisconnectedView {
    private func setupLayout() {
        backgroundColor = .black.withAlphaComponent(0.4)

        contentView.fView.image = .iconGameDisconnectedOverlay
        contentView.sView.text = String(localized: .Game.videoOverlayHostDisconnected)

        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.equalToSuperview().inset(32)
            make.top.greaterThanOrEqualToSuperview()
        }
    }
}
