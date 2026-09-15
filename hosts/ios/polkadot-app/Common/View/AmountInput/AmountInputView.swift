import UIKit
import UIKit_iOS
import DesignSystem
import PolkadotUI

class AmountInputView: UIControl {
    let iconView: AssetView = .create { view in
        view.isUserInteractionEnabled = false
    }

    let symbolLabel: Label = .create { label in
        label.typography = .displayExtraLarge
        label.textColor = .fgTertiary
    }

    let textField: UITextField = .create { textField in
        textField.apply(style: .init(
            font: UIFont.displayExtraLarge,
            textColor: .fgPrimary,
            tintColor: .fgPrimary
        ))

        textField.attributedPlaceholder = NSAttributedString(
            string: "0",
            attributes: [
                .foregroundColor: UIColor.fgTertiary,
                .font: UIFont.displayExtraLarge
            ]
        )

        textField.keyboardType = .decimalPad
    }

    var minFontSize: CGFloat = 24.0 {
        didSet {
            setNeedsLayout()
        }
    }

    var maxFontSize: CGFloat = 80.0 {
        didSet {
            setNeedsLayout()
        }
    }

    var horizontalSpacing: CGFloat = 8.0 {
        didSet {
            setNeedsLayout()
        }
    }

    var hasIcon: Bool {
        !iconView.isHidden
    }

    private(set) var inputViewModel: AmountInputViewModelProtocol?
    private(set) var isSymbolInFront: Bool = false

    var completed: Bool {
        if let inputViewModel {
            inputViewModel.isValid
        } else {
            false
        }
    }

    var hasValidNumber: Bool {
        inputViewModel?.decimalAmount != nil
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func bind(assetViewModel: AssetAmountViewModel) {
        symbolLabel.text = assetViewModel.symbol
        isSymbolInFront = assetViewModel.isSymbolInFront

        if let iconViewModel = assetViewModel.assetViewModel {
            iconView.isHidden = false
            iconView.bind(viewModel: iconViewModel)
        } else {
            iconView.isHidden = true
        }

        setNeedsLayout()
    }

    func bind(inputViewModel: AmountInputViewModelProtocol) {
        self.inputViewModel?.observable.remove(observer: self)
        inputViewModel.observable.add(observer: self)

        self.inputViewModel = inputViewModel

        textField.text = inputViewModel.displayAmount

        setNeedsLayout()
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        layoutContent()
    }

    private func getTextForEstimation() -> String {
        if isSymbolInFront {
            (symbolLabel.text ?? "") + (textField.text ?? "0")
        } else {
            (textField.text ?? "0") + (symbolLabel.text ?? "")
        }
    }

    private func calculateAvailableWidth() -> CGFloat {
        var availableWidth = bounds.width

        if hasIcon {
            availableWidth = max(availableWidth - iconView.prefererredSize - horizontalSpacing, 0)
        }

        if !isSymbolInFront {
            availableWidth = max(availableWidth - horizontalSpacing, 0)
        }

        return availableWidth
    }

    private func calculateLayoutWidth() -> CGFloat {
        var totalWidth = symbolLabel.intrinsicContentSize.width + textField.intrinsicContentSize.width

        if hasIcon {
            totalWidth += iconView.prefererredSize + horizontalSpacing
        }

        if !isSymbolInFront {
            totalWidth += horizontalSpacing
        }

        return min(totalWidth, bounds.width)
    }

    private func layoutIconIfNeeded(for totalWidth: CGFloat) {
        guard hasIcon else {
            return
        }

        let iconSize = iconView.prefererredSize

        iconView.frame = CGRect(
            x: bounds.midX - totalWidth / 2.0,
            y: bounds.midY - iconSize / 2.0,
            width: iconSize,
            height: iconSize
        )
    }

    private func layoutSymbol(for totalWidth: CGFloat) {
        let size = symbolLabel.intrinsicContentSize

        if isSymbolInFront {
            let iconWidth = hasIcon ? iconView.prefererredSize + horizontalSpacing : 0

            symbolLabel.frame = CGRect(
                x: bounds.midX - totalWidth / 2.0 + iconWidth,
                y: bounds.midY - size.height / 2.0,
                width: size.width,
                height: size.height
            )
        } else {
            symbolLabel.frame = CGRect(
                x: bounds.midX + totalWidth / 2.0 - size.width,
                y: bounds.midY - size.height / 2.0,
                width: size.width,
                height: size.height
            )
        }
    }

    private func layoutTextField(for totalWidth: CGFloat) {
        let size = textField.intrinsicContentSize

        if isSymbolInFront {
            let leadingX = symbolLabel.frame.maxX
            let trailingX = bounds.midX + totalWidth / 2.0
            let remainedWidth = max(trailingX - leadingX, 0)

            textField.frame = CGRect(
                x: leadingX,
                y: bounds.midY - size.height / 2.0,
                width: remainedWidth,
                height: size.height
            )
        } else {
            let leadingX = hasIcon ? iconView.frame.maxX + horizontalSpacing : bounds.midX - totalWidth / 2.0
            let trailingX = symbolLabel.frame.minX - horizontalSpacing

            let remainedWidth = max(trailingX - leadingX, 0)

            textField.frame = CGRect(
                x: leadingX,
                y: bounds.midY - size.height / 2.0,
                width: remainedWidth,
                height: size.height
            )
        }
    }

    private func layoutContent() {
        let availableWidth = calculateAvailableWidth()
        let estimatedText = getTextForEstimation()

        let fontName = symbolLabel.typography
            .map { UIFont.app($0).fontName } ?? symbolLabel.font.fontName
        let fontSize = estimatedText.estimateMaxFontSize(
            fittingWidthOf: CGSize(width: availableWidth, height: bounds.height),
            fontFamily: fontName,
            minSize: minFontSize,
            maxSize: maxFontSize
        )

        guard let font = UIFont(name: fontName, size: fontSize) else {
            return
        }

        symbolLabel.font = font
        textField.font = font

        let layoutWidth = calculateLayoutWidth()

        layoutIconIfNeeded(for: layoutWidth)
        layoutSymbol(for: layoutWidth)
        layoutTextField(for: layoutWidth)
    }

    // MARK: Configure

    private func configure() {
        backgroundColor = UIColor.clear

        configureContentViewIfNeeded()
        configureLocalHandlers()
        configureTextFieldHandlers()
    }

    private func configureLocalHandlers() {
        addTarget(self, action: #selector(actionTouchUpInside), for: .touchUpInside)
    }

    private func configureTextFieldHandlers() {
        textField.delegate = self
    }

    private func configureContentViewIfNeeded() {
        addSubview(iconView)
        addSubview(textField)
        addSubview(symbolLabel)
    }

    // MARK: Action

    @objc private func actionTouchUpInside() {
        textField.becomeFirstResponder()
    }
}

extension AmountInputView: UITextFieldDelegate {
    func textField(
        _: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        inputViewModel?.didReceiveReplacement(string, for: range) ?? false
    }

    func textFieldDidBeginEditing(_: UITextField) {
        sendActions(for: .editingDidBegin)
    }
}

extension AmountInputView: AmountInputViewModelObserver {
    func amountInputDidChange() {
        textField.text = inputViewModel?.displayAmount

        sendActions(for: .editingChanged)

        setNeedsLayout()
    }
}
