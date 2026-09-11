import UIKit
import UIKit_iOS
import PolkadotUI

final class GameVideoHeaderView: UIView {
    let closeButton: RoundedButton = create {
        $0.applyIconStyle()
        $0.setIcon(
            UIImage(resource: .chevronDown)
                .withTintColor(
                    .textAndIconsPrimaryDark,
                    renderingMode: .alwaysOriginal
                )
        )
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

extension GameVideoHeaderView {
    func bind(viewModel: GameVideoViewLayout.ViewModel) {
        closeButton.isHidden = viewModel.state != .waiting
    }
}

private extension GameVideoHeaderView {
    func setupLayout() {
        addSubview(closeButton)
        closeButton.snp.makeConstraints {
            $0.width.height.equalTo(40)
            $0.leading.equalToSuperview().inset(24)
            $0.top.bottom.equalToSuperview().inset(4)
        }
    }
}
