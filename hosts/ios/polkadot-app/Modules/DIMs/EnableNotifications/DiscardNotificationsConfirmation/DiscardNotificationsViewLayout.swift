import UIKit
import UIKit_iOS
import PolkadotUI
import DesignSystem

final class DiscardNotificationsViewLayout: BottomSheetBaseLayout {
    let titleLabel: Label = .create {
        $0.typography = .headlineSmall
        $0.textColor = .textAndIconsPrimaryDark
        $0.numberOfLines = 0
    }

    let enableButton: RoundedButton = .create { button in
        button.applyMainStyle()
    }

    let discardButton: RoundedButton = .create { button in
        button.applyDestructiveStyle()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    override func setupLayout() {
        super.setupLayout()
        configureLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private extension DiscardNotificationsViewLayout {
    func configureLayout() {
        addSubview(titleLabel)
        addSubview(enableButton)
        addSubview(discardButton)

        titleLabel.snp.makeConstraints {
            $0.top.equalToSuperview().inset(24)
            $0.leading.trailing.equalToSuperview().inset(32)
        }

        enableButton.snp.makeConstraints {
            $0.top.equalTo(titleLabel.snp.bottom).offset(32)
            $0.height.equalTo(UIConstants.actionHeight)
            $0.leading.trailing.equalToSuperview().inset(32)
        }

        discardButton.snp.makeConstraints {
            $0.top.equalTo(enableButton.snp.bottom).offset(8)
            $0.height.equalTo(UIConstants.actionHeight)
            $0.leading.trailing.equalToSuperview().inset(32)
            $0.bottom.equalTo(safeAreaLayoutGuide.snp.bottom).inset(24)
        }
    }
}

extension DiscardNotificationsViewLayout {
    struct ViewModel {
        let title: String
        let enableButtonTitle: String
        let discardButtonTitle: String
    }

    func bind(viewModel: ViewModel) {
        titleLabel.text = viewModel.title
        enableButton.setTitle(viewModel.enableButtonTitle)
        discardButton.setTitle(viewModel.discardButtonTitle)
    }
}
