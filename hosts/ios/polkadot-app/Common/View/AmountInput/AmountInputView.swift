import UIKit
import UIKit_iOS
import DesignSystem
import PolkadotUI

class AmountInputView: UIControl {
    let symbolLabel: Label = .create { label in
        label.typography = .displayExtraLarge
        label.textColor = .fgTertiary
    }

    let symbolImageView: UIImageView = .create { view in
        view.contentMode = .scaleAspectFit
        view.tintColor = .fgTertiary
        view.isHidden = true
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

    var maxFontSize: CGFloat = UIFont.displayExtraLarge.pointSize {
        didSet {
            setNeedsLayout()
        }
    }

    var horizontalSpacing: CGFloat = 8.0 {
        didSet {
            setNeedsLayout()
        }
    }

    /// Currency mark drawn in front of the amount, in addition to `symbolLabel`.
    var symbolImage: UIImage? {
        didSet {
            updateSymbolImage()
        }
    }

    var symbolImageRenderingMode: UIImage.RenderingMode = .alwaysTemplate {
        didSet {
            updateSymbolImage()
        }
    }

    private func updateSymbolImage() {
        symbolImageView.image = symbolImage?.withRenderingMode(symbolImageRenderingMode)
        symbolImageView.isHidden = symbolImage == nil

        setNeedsLayout()
    }

    var hasSymbolImage: Bool {
        !symbolImageView.isHidden
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

    private func calculateAvailableWidth(for fontName: String) -> CGFloat {
        var availableWidth = bounds.width

        // The mark scales with the font the estimation is about to pick, so reserve it at the
        // largest it can get. Reserving the drawn width instead would make the two depend on
        // each other and the amount jitter as it grows.
        if hasSymbolImage, let largestFont = UIFont(name: fontName, size: maxFontSize) {
            let reserved = symbolImageSize(for: largestFont).width + horizontalSpacing
            availableWidth = max(availableWidth - reserved, 0)
        }

        if !isSymbolInFront {
            availableWidth = max(availableWidth - horizontalSpacing, 0)
        }

        return availableWidth
    }

    private func calculateLayoutWidth(for font: UIFont) -> CGFloat {
        var totalWidth = symbolLabel.intrinsicContentSize.width + textField.intrinsicContentSize.width

        totalWidth += leadingContentWidth(for: font)

        if !isSymbolInFront {
            totalWidth += horizontalSpacing
        }

        return min(totalWidth, bounds.width)
    }

    private func layoutSymbolImageIfNeeded(for totalWidth: CGFloat, font: UIFont) {
        guard hasSymbolImage else {
            return
        }

        let size = symbolImageSize(for: font)

        // The digits are centred on midY, and the design centres the mark on the same line.
        symbolImageView.frame = CGRect(
            x: bounds.midX - totalWidth / 2.0,
            y: bounds.midY - size.height / 2.0,
            width: size.width,
            height: size.height
        )
    }

    private func layoutSymbol(for totalWidth: CGFloat, font: UIFont) {
        let size = symbolLabel.intrinsicContentSize

        if isSymbolInFront {
            let leadingWidth = leadingContentWidth(for: font)

            symbolLabel.frame = CGRect(
                x: bounds.midX - totalWidth / 2.0 + leadingWidth,
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

    private func layoutTextField(for totalWidth: CGFloat, font: UIFont) {
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
            let leadingX = bounds.midX - totalWidth / 2.0 + leadingContentWidth(for: font)
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
        let fontName = symbolLabel.typography
            .map { UIFont.app($0).fontName } ?? symbolLabel.font.fontName

        let availableWidth = calculateAvailableWidth(for: fontName)
        let estimatedText = getTextForEstimation()

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

        let layoutWidth = calculateLayoutWidth(for: font)

        layoutSymbolImageIfNeeded(for: layoutWidth, font: font)
        layoutSymbol(for: layoutWidth, font: font)
        layoutTextField(for: layoutWidth, font: font)
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
        addSubview(symbolImageView)
        addSubview(textField)
        addSubview(symbolLabel)
    }

    // MARK: Action

    @objc private func actionTouchUpInside() {
        textField.becomeFirstResponder()
    }
}

private extension AmountInputView {
    /// The design draws a 35pt mark next to 64pt digits; the ratio keeps that proportion as the
    /// amount shrinks to fit.
    static let symbolImageHeightRatio: CGFloat = 35.0 / 64.0

    func symbolImageSize(for font: UIFont) -> CGSize {
        guard let image = symbolImageView.image, image.size.height > 0 else {
            return .zero
        }

        let height = font.pointSize * Self.symbolImageHeightRatio

        return CGSize(width: height * image.size.width / image.size.height, height: height)
    }

    /// Everything drawn between the leading edge of the content and the digits.
    func leadingContentWidth(for font: UIFont) -> CGFloat {
        guard hasSymbolImage else {
            return 0
        }

        return symbolImageSize(for: font).width + horizontalSpacing
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
