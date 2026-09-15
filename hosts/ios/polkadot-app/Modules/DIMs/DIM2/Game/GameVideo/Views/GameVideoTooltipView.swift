import UIKit
import UIKit_iOS
import DesignSystem

final class GameVideoTooltipView: UIView {
    private let containerView: RoundedView = .create { view in
        view.applyBackgroundStyle(.white100, cornerRadius: Constants.cornerRadius)
    }

    private let imageWithTextView: ImageWithTitleView = .create { view in
        view.titleFont = UIFont.titleMedium
        view.titleColor = .textAndIconsPrimaryLight
        view.spacingBetweenLabelAndIcon = 8
    }

    private let arrowView: UIView = .create { view in
        view.backgroundColor = .clear
    }

    private let arrowLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
        setupArrow()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateArrowPath()
    }
}

// MARK: - Private

private extension GameVideoTooltipView {
    func setupLayout() {
        addSubview(containerView)
        containerView.addSubview(imageWithTextView)
        addSubview(arrowView)

        containerView.snp.makeConstraints {
            $0.top.leading.trailing.equalToSuperview()
        }

        imageWithTextView.snp.makeConstraints {
            $0.edges.equalToSuperview().inset(UIEdgeInsets(
                top: Constants.verticalPadding,
                left: Constants.horizontalPadding,
                bottom: Constants.verticalPadding,
                right: Constants.horizontalPadding
            ))
        }

        arrowView.snp.makeConstraints {
            $0.top.equalTo(containerView.snp.bottom)
            $0.centerX.equalToSuperview()
            $0.width.equalTo(Constants.arrowWidth)
            $0.height.equalTo(Constants.arrowHeight)
            $0.bottom.equalToSuperview()
        }
    }

    func setupArrow() {
        arrowLayer.fillColor = UIColor.textAndIconsPrimaryDark.cgColor
        arrowView.layer.addSublayer(arrowLayer)
    }

    func updateArrowPath() {
        let width = arrowView.bounds.width
        let height = arrowView.bounds.height

        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: width / 2, y: height))
        path.addLine(to: CGPoint(x: width, y: 0))
        path.close()

        arrowLayer.path = path.cgPath
        arrowLayer.frame = arrowView.bounds
    }
}

// MARK: - Internal

extension GameVideoTooltipView {
    func bind(viewModel: ViewModel) {
        imageWithTextView.title = viewModel.text
        imageWithTextView.iconImage = viewModel.icon

        arrowView.isHidden = !viewModel.showsArrow

        if viewModel.showsArrow {
            containerView.snp.remakeConstraints {
                $0.top.leading.trailing.equalToSuperview()
            }
            arrowView.snp.remakeConstraints {
                $0.top.equalTo(containerView.snp.bottom)
                $0.centerX.equalToSuperview()
                $0.width.equalTo(Constants.arrowWidth)
                $0.height.equalTo(Constants.arrowHeight)
                $0.bottom.equalToSuperview()
            }
        } else {
            containerView.snp.remakeConstraints {
                $0.edges.equalToSuperview()
            }
        }
    }
}

// MARK: - View Model

extension GameVideoTooltipView {
    enum ViewModel: Equatable {
        case showGesture
        case copyHost
        case swipeHint

        var text: String {
            switch self {
            case .showGesture: String(localized: .Game.gameVideoShowGesture)
            case .copyHost: String(localized: .Game.gameVideoCopyGesture)
            case .swipeHint: String(localized: .Game.gameVideoSwipeUsersHint)
            }
        }

        var icon: UIImage? {
            switch self {
            case .showGesture: .wavingHand
            case .copyHost: .frontHand
            case .swipeHint: .swipeHand
            }
        }

        var showsArrow: Bool {
            switch self {
            case .showGesture,
                 .copyHost: true
            case .swipeHint: false
            }
        }
    }
}

// MARK: - Constants

private extension GameVideoTooltipView {
    enum Constants {
        static let cornerRadius: CGFloat = 24
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 11
        static let arrowWidth: CGFloat = 27
        static let arrowHeight: CGFloat = 14
    }
}
