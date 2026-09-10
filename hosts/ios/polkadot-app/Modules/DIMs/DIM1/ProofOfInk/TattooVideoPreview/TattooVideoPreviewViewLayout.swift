import UIKit
import UIKit_iOS
import PolkadotUI
import DesignSystem

final class TattooVideoPreviewViewLayout: UIView {
    let titleLabel: Label = .create { label in
        label.typography = .titleLarge
        label.textColor = .textAndIconsPrimaryDark
    }

    let playerView = VideoPlayerView()

    var actionButton: RoundedButton {
        actionLoadingView.actionButton
    }

    let actionLoadingView: LoadableActionView = .create { view in
        view.applyMainStyle()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        setupStyle()
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupStyle() {
        backgroundColor = .black100
    }

    private func setupLayout() {
        addSubview(playerView)
        playerView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalToSuperview()
            make.height.equalTo(snp.width)
        }

        addSubview(actionLoadingView)
        actionLoadingView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.bottom.equalTo(safeAreaLayoutGuide.snp.bottom).offset(-16)
            make.height.equalTo(UIConstants.actionHeight)
        }
    }
}
