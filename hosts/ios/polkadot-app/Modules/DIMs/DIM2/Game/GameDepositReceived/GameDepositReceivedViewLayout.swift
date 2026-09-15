import UIKit
import UIKit_iOS
import PolkadotUI
import DesignSystem

final class GameDepositReceivedViewLayout: BottomSheetBaseLayout {
    let titleLabel: Label = create {
        $0.typography = .headlineSmall
        $0.textColor = .fgPrimary
        $0.textAlignment = .center
        $0.numberOfLines = 0
    }

    let buttonsContainer: GenericPairValueView<RoundedButton, RoundedButton> = create {
        $0.stackView.spacing = 8
        $0.stackView.distribution = .fillEqually
        $0.stackView.axis = .horizontal

        $0.fView.applySecondaryStyle()
        $0.sView.applyMainStyle()
    }

    var registerButton: RoundedButton {
        buttonsContainer.sView
    }

    var registerLaterButton: RoundedButton {
        buttonsContainer.fView
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setupLayout() {
        super.setupLayout()

        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints {
            $0.leading.trailing.top.equalToSuperview().inset(16)
        }

        contentView.addSubview(buttonsContainer)
        buttonsContainer.snp.makeConstraints {
            $0.height.equalTo(UIConstants.actionHeight)
            $0.top.equalTo(titleLabel.snp.bottom).offset(40)
            $0.leading.trailing.equalToSuperview()
            $0.bottom.equalToSuperview().inset(8)
        }
    }
}

extension GameDepositReceivedViewLayout {
    struct ViewModel {
        let details: String
        let registerButtonText: String?
        let skipButtonText: String
    }

    func bind(viewModel: ViewModel) {
        if let registerButtonText = viewModel.registerButtonText {
            registerButton.setTitle(registerButtonText)
            registerButton.isHidden = false
        } else {
            registerButton.isHidden = true
        }
        registerLaterButton.setTitle(viewModel.skipButtonText)
        titleLabel.text = viewModel.details
    }
}
