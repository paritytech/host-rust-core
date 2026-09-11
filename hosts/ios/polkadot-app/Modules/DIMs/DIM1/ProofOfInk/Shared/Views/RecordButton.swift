import Foundation
import UIKit_iOS
import UIKit

extension RecordButton {
    enum State {
        case actionable
        case recording
        case processing
    }
}

final class RecordButton: BackgroundedContentControl {
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .rigid)

    private var outerBackgroundView: RoundedView? {
        backgroundView as? RoundedView
    }

    private var innerContentView: RecordContentView? {
        contentView as? RecordContentView
    }

    private let activityIndicator: UIActivityIndicatorView = .create { view in
        view.style = .medium
        view.color = .white100
        view.hidesWhenStopped = true
    }

    var viewState: State = .actionable {
        didSet {
            updateTo(viewState: viewState)
        }
    }

    var isRecording: Bool {
        innerContentView?.isRecording ?? false
    }

    var outerInnerSpacing: CGFloat = 0.0 {
        didSet {
            setNeedsLayout()
        }
    }

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        setupBackgroundView()
        setupContentView()
        setupActivityIndicator()
        setupHapticFeedbackOnTap()

        apply(style: Self.defaultStyle)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(style: RecordButton.Style) {
        outerBackgroundView?.fillColor = .clear
        outerBackgroundView?.highlightedFillColor = .clear
        outerBackgroundView?.strokeColor = style.outerStrokeColor
        outerBackgroundView?.highlightedStrokeColor = style.outerStrokeColor
        outerBackgroundView?.strokeWidth = style.outerStrokeWidth
        innerContentView?.fillColor = style.innerFillColor
        innerContentView?.highlightedFillColor = style.innerFillColor

        changesContentOpacityWhenHighlighted = true
    }

    override func layoutSubviews() {
        guard let outerBackgroundView, let innerContentView else {
            return
        }

        outerBackgroundView.frame = bounds
        outerBackgroundView.cornerRadius = bounds.height / 2.0

        let innerWidth = max(bounds.width - 2 * outerBackgroundView.strokeWidth - 2 * outerInnerSpacing, 0)
        let innerHeight = max(bounds.height - 2 * outerBackgroundView.strokeWidth - 2 * outerInnerSpacing, 0)

        innerContentView.frame = CGRect(
            x: bounds.midX - innerWidth / 2,
            y: bounds.midY - innerHeight / 2,
            width: innerWidth,
            height: innerHeight
        )
    }

    override func set(highlighted: Bool, animated _: Bool) {
        // Disable animation to be able to disable interaction on touch end to present activity indicator
        super.set(highlighted: highlighted, animated: false)
    }
}

private extension RecordButton {
    func updateTo(viewState: State) {
        switch viewState {
        case .actionable:
            isEnabled = true
            isUserInteractionEnabled = true
            innerContentView?.isRecording = false
            activityIndicator.stopAnimating()
        case .recording:
            isEnabled = true
            isUserInteractionEnabled = true
            innerContentView?.isRecording = true
            activityIndicator.stopAnimating()
        case .processing:
            isEnabled = false
            isUserInteractionEnabled = false
            innerContentView?.isRecording = false
            activityIndicator.startAnimating()
        }
    }

    func setupActivityIndicator() {
        addSubview(activityIndicator)
        activityIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    func setupHapticFeedbackOnTap() {
        feedbackGenerator.prepare()
        addTarget(self, action: #selector(handleTouchUpInside), for: .touchDown)
    }

    func setupBackgroundView() {
        backgroundView = RoundedView()
        backgroundView?.isUserInteractionEnabled = false
    }

    func setupContentView() {
        contentView = RecordContentView()
        contentView?.isUserInteractionEnabled = false
    }

    @objc
    func handleTouchUpInside() {
        feedbackGenerator.impactOccurred()
        feedbackGenerator.prepare()
    }
}

extension RecordButton {
    struct Style {
        let outerStrokeColor: UIColor
        let outerStrokeWidth: CGFloat
        let spacing: CGFloat
        let innerFillColor: UIColor
    }

    static var defaultStyle: Style {
        .init(
            outerStrokeColor: .white100,
            outerStrokeWidth: 6,
            spacing: 2,
            innerFillColor: .brandPink
        )
    }
}

final class RecordContentView: ShapeView {
    var shapesRatio: CGFloat = 0.66 {
        didSet {
            applyPath()
        }
    }

    var recordingCornerRadius: CGFloat = 12 {
        didSet {
            applyPath()
        }
    }

    var isRecording: Bool = false {
        didSet {
            applyPath()
        }
    }

    override var shapePath: UIBezierPath {
        let radius = bounds.height / 2.0

        if isRecording {
            let halfSide = shapesRatio * radius
            let rect = CGRect(
                x: bounds.midX - halfSide,
                y: bounds.midY - halfSide,
                width: 2 * halfSide,
                height: 2 * halfSide
            )

            return UIBezierPath(roundedRect: rect, cornerRadius: recordingCornerRadius)
        } else {
            let rect = CGRect(
                x: bounds.midX - radius,
                y: bounds.midY - radius,
                width: 2 * radius,
                height: 2 * radius
            )

            return UIBezierPath(roundedRect: rect, cornerRadius: radius)
        }
    }
}
