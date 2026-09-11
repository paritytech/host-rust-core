import UIKit
import UIKit_iOS
import SnapKit
import SwiftUI
import ExternalAccessibility
import PolkadotUI
import DesignSystem

final class TransferAmountViewLayout: UIView, AdaptiveDesignable {
    var addressInputViewController: UIHostingController<RecipientLabelView>?

    private let actionModel = TransferActionButtonModel()

    private lazy var transferButtonController: TransferActionButtonController = {
        let view = TransferActionButtonView(model: actionModel)
        let controller = TransferActionButtonController(rootView: view)
        controller.view.backgroundColor = .clear
        controller.safeAreaRegions = []
        return controller
    }()

    let issueLabel: PolkadotUI.Label = .create { view in
        view.typography = .bodyLarge
        view.textColor = .fgError
        view.numberOfLines = 3
        view.textAlignment = .center
    }

    var onAction: (() -> Void)?

    let balanceView = BalanceView()

    let infoButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(resource: .iconInfo20), for: .normal)
        button.tintColor = .fgSecondary
        return button
    }()

    let privacyHintLabel: PolkadotUI.Label = .create {
        $0.typography = .bodyMedium
        $0.textColor = .fgSecondary
        $0.numberOfLines = 0
        $0.textAlignment = .center
        $0.isHidden = true
    }

    let amountInputView = AmountInputView()

    let cashLabel: PolkadotUI.Label = .create {
        $0.text = String(localized: .tokenName)
        $0.typography = .titleExtraLarge
        $0.textColor = .fgSecondary
    }

    var heightScaleMultiplier: CGFloat {
        let ratio = designScaleRatio.height * UIConstants.mockupsScaleRatioHeight

        return ratio < 1 ? ratio : 1
    }

    let feeView = TitleBalanceView()

    #if TESTNET_FEATURE
        let debugStrategyView: UIView = {
            let view = UIView()
            view.backgroundColor = UIColor.black.withAlphaComponent(0.8)
            view.layer.cornerRadius = 12
            view.isHidden = true
            return view
        }()

        let debugStrategyLabel: UILabel = {
            let label = UILabel()
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = .white
            label.numberOfLines = 0
            return label
        }()
    #endif

    var bottomView: UIStackView?

    override init(frame: CGRect) {
        super.init(frame: frame)

        actionModel.action = { [weak self] in
            self?.onAction?()
        }

        backgroundColor = .bgSurfaceMain
        feeView.changesContentOpacityWhenHighlighted = false

        setupLayout()
        applyAccessibilityBindings()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setActionAmount(_ value: String) {
        actionModel.title = String(localized: .transferActionSend(value))
    }

    func adoptToVisibleKeyboard(bottomInset: CGFloat) {
        bottomView?.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(UIConstants.horizontalInsetMedium)
            make.bottom.equalToSuperview().inset(bottomInset + 24 * heightScaleMultiplier)
        }
    }

    func adoptToHiddenKeyboard() {
        bottomView?.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(UIConstants.horizontalInsetMedium)
            make.bottom.equalTo(safeAreaLayoutGuide.snp.bottom).offset(-24)
        }
    }

    func setupLayout() {
        balanceView.apply(style: .normal)

        addSubview(balanceView)
        addSubview(infoButton)

        balanceView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(safeAreaLayoutGuide.snp.top).offset(132 * heightScaleMultiplier)
            make.height.equalTo(balanceView.preferredHeight ?? 0)
        }
        infoButton.snp.makeConstraints { make in
            make.size.equalTo(20)
            make.leading.equalTo(balanceView.snp.trailing).offset(DSSpacings.extraSmall)
            make.trailing.lessThanOrEqualToSuperview().inset(24)
            make.centerY.equalTo(balanceView)
        }

        addSubview(privacyHintLabel)
        privacyHintLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.top.equalTo(balanceView.snp.bottom).offset(DSSpacings.extraSmall)
        }

        addSubview(amountInputView)
        amountInputView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.top.equalTo(privacyHintLabel.snp.bottom).offset(8)
            make.height.equalTo(88)
        }

        addSubview(cashLabel)
        cashLabel.snp.makeConstraints { make in
            make.centerX.equalTo(amountInputView.textField.snp.centerX)
            make.top.equalTo(amountInputView.snp.bottom).offset(DSSpacings.medium)
        }

        let bottomView = UIView.vStack(spacing: 12 * heightScaleMultiplier, [feeView, confirmView])
        self.bottomView = bottomView

        confirmView.snp.makeConstraints { make in
            make.height.equalTo(UIConstants.actionHeight)
        }

        addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(UIConstants.horizontalInsetMedium)
            make.bottom.equalTo(safeAreaLayoutGuide.snp.bottom).offset(-24 * heightScaleMultiplier)
        }

        issueLabel.isHidden = true
        addSubview(issueLabel)
        issueLabel.snp.makeConstraints { make in
            make.top.equalTo(cashLabel.snp.bottom).offset(DSSpacings.medium)
            make.centerX.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(UIConstants.horizontalInsetWide)
        }

        #if TESTNET_FEATURE
            setupDebugStrategyView()
        #endif
    }

    var isLoading: Bool {
        actionModel.isLoading
    }

    func bind(state: TransferConfirmState) {
        switch state {
        case let .loading(status):
            actionModel.isLoading = true
            actionModel.statusText = status
        case .confirm:
            actionModel.isLoading = false
            actionModel.isActive = true
        case let .issue(title):
            actionModel.isLoading = false
            actionModel.isActive = false
            actionModel.title = title
        }
    }

    func bind(transferStatus: String) {
        withAnimation {
            actionModel.statusText = transferStatus
        }
    }

    var confirmView: UIView {
        transferButtonController.view
    }

    func bind(privacyHint: String?) {
        privacyHintLabel.text = privacyHint
        privacyHintLabel.isHidden = privacyHint == nil
    }

    func bind(recipient: TransferRecipientViewModel) {
        addressInputViewController?.view.removeFromSuperview()

        let title: String = recipient.username ?? recipient.address
        let avatar = AvatarViewModel.colored(
            text: String(title.prefix(1)),
            colorSeed: recipient.address
        )

        let controller = UIHostingController(
            rootView: RecipientLabelView(avatar: avatar, title: title)
        )
        controller.view.backgroundColor = .clear
        addressInputViewController = controller

        addSubview(controller.view)
        controller.view.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.top.equalTo(safeAreaLayoutGuide.snp.top)
            make.height.equalTo(56)
        }
    }
}

enum TransferConfirmState {
    case loading(status: String?)
    case confirm
    case issue(String)
}

// MARK: - DEBUG

extension TransferAmountViewLayout {
    #if TESTNET_FEATURE
        private func setupDebugStrategyView() {
            addSubview(debugStrategyView)
            debugStrategyView.addSubview(debugStrategyLabel)

            debugStrategyView.snp.makeConstraints { make in
                make.leading.trailing.equalToSuperview().inset(UIConstants.horizontalInsetMedium)
                make.bottom.equalTo(feeView.snp.top).offset(-12)
            }

            debugStrategyLabel.snp.makeConstraints { make in
                make.edges.equalToSuperview().inset(12)
            }
        }

        func bind(strategyDebugInfo: TransferStrategyDebugInfo?) {
            guard let info = strategyDebugInfo else {
                debugStrategyView.isHidden = true
                return
            }

            var text = "[DEBUG] Strategy: \(info.strategyType.rawValue)"

            if !info.coinsUsed.isEmpty {
                text += "\n\nCoins used:"
                for coin in info.coinsUsed {
                    text += "\n  idx=\(coin.derivationIndex)  exp=2^\(coin.exponent)"
                }
            }

            if let splitInfo = info.splitInfo {
                text += "\n\nSplit from coin:"
                text += "\n  idx=\(splitInfo.overflowCoin.derivationIndex)  exp=2^\(splitInfo.overflowCoin.exponent)"
                if !splitInfo.targetDenominations.isEmpty {
                    text += "\n\nTarget denominations: \(splitInfo.targetDenominations.map { "2^\($0)" }.joined(with: .commaSpace))"
                }
                if !splitInfo.changeDenominations.isEmpty {
                    text += "\nChange denominations: \(splitInfo.changeDenominations.map { "2^\($0)" }.joined(with: .commaSpace))"
                }
            }

            if !info.vouchersToUnload.isEmpty {
                text += "\n\nVouchers to unload:"
                for voucher in info.vouchersToUnload {
                    text += "\n  idx=\(voucher.derivationIndex)  exp=2^\(voucher.exponent)"
                }
            }

            debugStrategyLabel.text = text
            debugStrategyView.isHidden = false
        }
    #endif
}

// MARK: - AccessibilityBound

extension TransferAmountViewLayout: AccessibilityBound {
    var accessibilityBindings: [AccessibilityBinding] {
        [
            .init(balanceView.titleLabel, AccessibilityID.TransferAmount.availableBalanceLabel),
            .init(balanceView.amountLabel, AccessibilityID.TransferAmount.availableBalanceValue),
            .init(amountInputView.symbolLabel, AccessibilityID.TransferAmount.currencyLabel),
            .init(amountInputView.textField, AccessibilityID.TransferAmount.input)
        ]
    }
}
