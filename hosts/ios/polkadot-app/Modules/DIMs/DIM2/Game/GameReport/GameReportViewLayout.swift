import UIKit
import UIKit_iOS
import PolkadotUI

final class GameReportViewLayout: UIView {
    var didRequestToggle: ((GameVote) -> Void)?
    var didRequestRegister: (() -> Void)?

    private let stripeBackgroundView = DiagonalStripeBackgroundView(frame: .zero)

    private let collectionView: UICollectionView = {
        let layout = GameReportCollectionViewLayout.layout()
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.register(
            GameReportCell.self,
            forCellWithReuseIdentifier: GameReportCell.identifier
        )
        view.register(
            GameReportHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: GameReportHeaderView.identifier
        )
        return view
    }()

    private let confirmView: GenericConfirmView<GameReportConfirmButton> = create {
        $0.actionButton.setTitle(String(localized: .Game.gameReportConfirmAction))
        $0.bind(state: .confirm)
    }

    private var endedView: GameReportEndedView?
    private var loadingIndicator: ActivityIndicatorView?

    private var gameVotes = [GameVote]()

    var confirmButton: UIControl {
        confirmView.actionButton
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
        collectionView.dataSource = self
        collectionView.delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class GameReportConfirmButton: UIControl {
    private let glowView: UIView = create {
        $0.backgroundColor = UIColor(resource: .dim2ConfirmButtonGradientStart)
        $0.layer.cornerRadius = GameReportConfirmButtonConstants.cornerRadius
        $0.layer.shadowColor = UIColor(resource: .dim2ConfirmButtonGradientStart).cgColor
        $0.layer.shadowOpacity = 0.85
        $0.layer.shadowRadius = 32
        $0.layer.shadowOffset = CGSize(width: 0, height: 6)
        $0.isUserInteractionEnabled = false
    }

    private let gradientView: GameReportConfirmButtonGradientView = create {
        $0.colors = GameReportConfirmButtonConstants.gradientColors
        $0.locations = GameReportConfirmButtonConstants.gradientLocations.map(Float.init)
        $0.startPoint = CGPoint(x: 0.5, y: 0)
        $0.endPoint = CGPoint(x: 0.5, y: 1)
        $0.cornerRadius = GameReportConfirmButtonConstants.cornerRadius
        $0.isUserInteractionEnabled = false
    }

    private let progressFillView: UIView = create {
        $0.backgroundColor = UIColor.white24
        $0.isUserInteractionEnabled = false
    }

    private let titleLabel: UILabel = create {
        $0.textAlignment = .center
        $0.isUserInteractionEnabled = false
    }

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.72 : 1
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIConstants.actionHeight)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setTitle(_ title: String) {
        titleLabel.attributedText = LabelStyle.buttonMulishExtraBlack().attributedString(
            from: title,
            textColor: .white,
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        accessibilityLabel = title
    }

    func bind(state: GameReportViewLayout.ConfirmButtonState) {
        switch state {
        case .confirm:
            setTitle(String(localized: .Game.gameReportConfirmAction))
            setProgress(0)
            isEnabled = true

        case let .autoConfirm(secondsRemaining, progress):
            setTitle(confirmingCountdownTitle(secondsRemaining: secondsRemaining))
            setProgress(progress, animated: true)
            isEnabled = true

        case .confirming:
            setTitle(confirmingTitle)
            setProgress(1)
            isEnabled = false

        case .loading:
            break
        }
    }
}

private final class GameReportConfirmButtonGradientView: UIView {
    var cornerRadius: CGFloat = 0 {
        didSet {
            gradientLayer?.cornerRadius = cornerRadius
            gradientLayer?.masksToBounds = cornerRadius > 0
        }
    }

    var colors: [UIColor] = [] {
        didSet {
            gradientLayer?.colors = colors.map(\.cgColor)
        }
    }

    var locations: [Float]? {
        didSet {
            gradientLayer?.locations = locations?.map(NSNumber.init(value:))
        }
    }

    var startPoint = CGPoint(x: 0.5, y: 0) {
        didSet {
            gradientLayer?.startPoint = startPoint
        }
    }

    var endPoint = CGPoint(x: 0.5, y: 1) {
        didSet {
            gradientLayer?.endPoint = endPoint
        }
    }

    private var gradientLayer: CAGradientLayer? {
        layer as? CAGradientLayer
    }

    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private enum GameReportConfirmButtonConstants {
    static let cornerRadius = CGFloat(12)
    static let gradientColors = [
        UIColor(resource: .dim2ConfirmButtonGradientStart),
        UIColor(resource: .dim2ConfirmButtonGradientMiddle),
        UIColor(resource: .dim2ConfirmButtonGradientEnd)
    ]
    static let gradientLocations = [CGFloat(0), CGFloat(0.52), CGFloat(1)]
    static let progressAnimationDuration = TimeInterval(1)
}

private extension GameReportConfirmButton {
    func setupLayout() {
        addSubview(glowView)
        glowView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        addSubview(gradientView)
        gradientView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        gradientView.addSubview(progressFillView)

        addSubview(titleLabel)
        titleLabel.snp.makeConstraints {
            $0.edges.equalToSuperview().inset(8)
        }
    }
}

extension GameReportViewLayout {
    enum ConfirmButtonState: Equatable {
        case confirm
        case autoConfirm(secondsRemaining: Int, progress: CGFloat)
        case confirming
        case loading
    }

    enum ViewModel {
        case loading
        case reporting(votes: [GameVote], confirmButtonState: ConfirmButtonState)
        case ended(gameTitle: String)
    }

    func bind(viewModel: ViewModel) {
        switch viewModel {
        case .loading:
            endedView?.removeFromSuperview()
            endedView = nil
            collectionView.isHidden = true
            confirmView.isHidden = true

            let indicator = loadingIndicator ?? makeLoadingIndicator()
            indicator.startAnimating()

        case let .reporting(votes, confirmButtonState):
            stopLoadingIndicator()
            endedView?.removeFromSuperview()
            endedView = nil

            collectionView.isHidden = false
            confirmView.isHidden = false

            gameVotes = votes
            collectionView.reloadData()

            bind(confirmButtonState: confirmButtonState)

        case let .ended(gameTitle):
            stopLoadingIndicator()
            collectionView.isHidden = true
            confirmView.isHidden = true

            let ended = endedView ?? makeEndedView()
            ended.bind(title: gameTitle)

            isUserInteractionEnabled = true
        }
    }

    func bind(confirmButtonState: ConfirmButtonState) {
        isUserInteractionEnabled = confirmButtonState.allowsUserInteraction
        bindConfirmView(state: confirmButtonState)
    }
}

extension GameReportViewLayout: UICollectionViewDataSource {
    func collectionView(
        _: UICollectionView,
        numberOfItemsInSection _: Int
    ) -> Int {
        gameVotes.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: GameReportCell.identifier,
            for: indexPath
        ) as? GameReportCell else {
            return UICollectionViewCell()
        }
        cell.bind(gameVote: gameVotes[indexPath.row])
        return cell
    }

    func collectionView(
        _: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: GameReportHeaderView.identifier,
            for: indexPath
        )
    }
}

extension GameReportViewLayout: UICollectionViewDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        collectionView.deselectItem(at: indexPath, animated: true)
        didRequestToggle?(gameVotes[indexPath.row])
    }
}

private extension GameReportViewLayout {
    func bindConfirmView(state: ConfirmButtonState) {
        switch state {
        case .loading:
            confirmView.bind(state: .loading)

        case .confirm,
             .autoConfirm,
             .confirming:
            confirmView.bind(state: .confirm)
        }

        confirmView.actionButton.bind(state: state)
    }

    func makeLoadingIndicator() -> ActivityIndicatorView {
        let indicator = ActivityIndicatorView()
        addSubview(indicator)
        indicator.snp.makeConstraints {
            $0.center.equalToSuperview()
        }
        loadingIndicator = indicator
        return indicator
    }

    func stopLoadingIndicator() {
        loadingIndicator?.stopAnimating()
        loadingIndicator?.removeFromSuperview()
        loadingIndicator = nil
    }

    func makeEndedView() -> GameReportEndedView {
        let view = GameReportEndedView()
        addSubview(view)
        view.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }
        view.actionButton.addTarget(self, action: #selector(handleRegister), for: .touchUpInside)
        endedView = view
        return view
    }

    @objc
    func handleRegister() {
        didRequestRegister?()
    }

    func setupLayout() {
        backgroundColor = .bgSurfaceMain
        collectionView.backgroundColor = .clear

        addSubview(stripeBackgroundView)
        stripeBackgroundView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        addSubview(confirmView)
        confirmView.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(16)
            $0.bottom.equalTo(safeAreaLayoutGuide.snp.bottom).inset(8)
            $0.height.equalTo(UIConstants.actionHeight)
        }

        let bottomScrollInset = UIConstants.actionHeight + 16
        collectionView.contentInset.bottom = bottomScrollInset
        collectionView.verticalScrollIndicatorInsets.bottom = bottomScrollInset
    }
}

private extension GameReportViewLayout.ConfirmButtonState {
    var allowsUserInteraction: Bool {
        switch self {
        case .confirm,
             .autoConfirm:
            true
        case .confirming,
             .loading:
            false
        }
    }
}

private extension GameReportConfirmButton {
    var confirmingTitle: String {
        String(localized: .Game.gameReportConfirmingAction)
    }

    func confirmingCountdownTitle(secondsRemaining: Int) -> String {
        String(localized: .Game.gameReportConfirmingCountdown("\(secondsRemaining)"))
    }

    func setProgress(_ progress: CGFloat, animated: Bool = false) {
        let progress = min(max(progress, 0), 1)

        guard animated, bounds.width > 0 else {
            progressFillView.layer.removeAllAnimations()
            updateProgressFillFrame(progress)
            return
        }

        if progressFillView.frame.height != bounds.height {
            progressFillView.frame = CGRect(
                x: 0,
                y: 0,
                width: progressFillView.frame.width,
                height: bounds.height
            )
        }

        UIView.animate(
            withDuration: GameReportConfirmButtonConstants.progressAnimationDuration,
            delay: 0,
            options: [.beginFromCurrentState, .curveLinear, .allowUserInteraction]
        ) {
            self.updateProgressFillFrame(progress)
        }
    }

    func updateProgressFillFrame(_ progress: CGFloat) {
        let progressWidth = bounds.width * progress
        progressFillView.frame = CGRect(
            x: 0,
            y: 0,
            width: progressWidth,
            height: bounds.height
        )
    }
}
