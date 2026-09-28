import DesignSystem
import UIKit
internal import SnapKit

public final class ScanPanelViewLayout: UIView {
    private enum Constants {
        static let compactCameraWidthRatio: CGFloat = 0.25
    }

    public let searchRow = DSSearchRowView()
    public let resultsView = SearchContactResultsView()

    /// Stands in for the camera while `AVCaptureSession` configures and starts, which takes
    /// roughly a second. It sits behind the preview, which fades in over it.
    private let placeholderView: UIView = {
        let view = UIView()
        view.backgroundColor = .bgSurfaceNested
        view.layer.cornerRadius = DSRadii.large
        view.layer.masksToBounds = true
        return view
    }()

    private lazy var cameraTapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(cameraTapped))
        recognizer.isEnabled = false
        return recognizer
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        return stack
    }()

    private var fullCameraWidthConstraint: Constraint?
    private var compactCameraWidthConstraint: Constraint?
    private var resultsCollapsedConstraint: Constraint?

    public var onCameraTapped: (() -> Void)?

    override public init(frame: CGRect) {
        super.init(frame: frame)

        resultsView.clipsToBounds = true
        contentStack.addArrangedSubview(resultsView)
        addSubview(contentStack)
        addSubview(searchRow)

        searchRow.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(DSSpacings.mediumIncreased)
            make.bottom.equalToSuperview().inset(DSSpacings.small)
        }

        contentStack.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(searchRow.snp.top).offset(-DSSpacings.small)
        }

        resultsView.snp.makeConstraints { make in
            make.width.equalTo(contentStack).offset(-DSSpacings.small * 2)
            resultsCollapsedConstraint = make.height.equalTo(0).constraint
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setupScannerView(_ scannerView: UIView) {
        contentStack.addArrangedSubview(scannerView)
        insertSubview(placeholderView, at: 0)

        placeholderView.snp.makeConstraints { make in
            make.edges.equalTo(scannerView)
        }

        scannerView.snp.makeConstraints { make in
            fullCameraWidthConstraint = make.width.equalTo(contentStack)
                .offset(-DSSpacings.mediumIncreased * 2).constraint
            compactCameraWidthConstraint = make.width.equalTo(contentStack)
                .multipliedBy(Constants.compactCameraWidthRatio).constraint
        }

        scannerView.addGestureRecognizer(cameraTapRecognizer)
        setSearchFocused(false)
    }

    /// Unfocused implies no results, so the late empty snapshot from the interactor changes nothing
    /// visible. The collapse is a constraint, not the stack's animated hide, because the panel
    /// measures its height mid-animation and the hide still reports the rows' height then.
    public func setSearchFocused(_ focused: Bool) {
        if focused {
            resultsCollapsedConstraint?.deactivate()
        } else {
            resultsCollapsedConstraint?.activate()
        }
        resultsView.alpha = focused ? 1 : 0
        contentStack.directionalLayoutMargins.top = focused ? DSSpacings.tiny : DSSpacings.mediumIncreased

        if focused {
            fullCameraWidthConstraint?.deactivate()
            compactCameraWidthConstraint?.activate()
        } else {
            compactCameraWidthConstraint?.deactivate()
            fullCameraWidthConstraint?.activate()
        }

        searchRow.setCancelVisible(focused)
        cameraTapRecognizer.isEnabled = focused
    }
}

private extension ScanPanelViewLayout {
    @objc func cameraTapped() {
        onCameraTapped?()
    }
}
