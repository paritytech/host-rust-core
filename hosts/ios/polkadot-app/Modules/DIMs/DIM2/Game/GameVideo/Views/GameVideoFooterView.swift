import SwiftUI
import UIKit
import UIKit_iOS
import PolkadotUI
import DesignSystem

final class GameVideoFooterView: UIView {
    private enum ProgressState {
        case hidden
        case progressView
    }

    let tutorialButton: RoundedButton = create {
        $0.applyGameVideoFooterActionStyle()
    }

    private let textLabel: PolkadotUI.Label = create {
        $0.numberOfLines = 1
        $0.typography = .titleLarge
        $0.textColor = .fgPrimary
        $0.textAlignment = .center
    }

    private lazy var progressView: ProgressView = {
        let progressView = ProgressView(frame: .zero)
        progressView.alpha = 0
        progressView.isHidden = true
        progressView.transform = hiddenProgressTransform
        return progressView
    }()

    private var progressState = ProgressState.hidden

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension GameVideoFooterView {
    func bind(viewModel: GameVideoViewLayout.ViewModel) {
        switch viewModel.state {
        case .waiting:
            applyWaitingState()
        case .subroundStart:
            applySubroundStartState()
        case .hosting,
             .hostingEnd:
            applyHostingState(viewModel: viewModel)
        case .hostIntroduction:
            setupAsHidden()
        }
    }
}

private extension RoundedButton {
    func applyGameVideoFooterActionStyle() {
        roundedBackgroundView?.fillColor = .dim2GameVideoFooterButtonBackground
        roundedBackgroundView?.highlightedFillColor = .dim2GameVideoFooterButtonBackground
        roundedBackgroundView?.strokeColor = .appliedStroke
        roundedBackgroundView?.strokeWidth = 1.0
        roundedBackgroundView?.highlightedStrokeColor = .clear
        roundedBackgroundView?.cornerRadius = 16
        roundedBackgroundView?.shadowColor = .white
        roundedBackgroundView?.shadowOpacity = 0.3
        roundedBackgroundView?.shadowRadius = 8
        roundedBackgroundView?.shadowOffset = .zero

        imageWithTitleView?.title = String(localized: .Game.gameVideoTutorialButtonTitle)
        imageWithTitleView?.titleColor = UIColor(resource: .textAndIconsSecondary)
        imageWithTitleView?.titleFont = .buttonMulishExtraBlack()

        contentInsets = .init(top: 0, left: 16, bottom: 0, right: 16)
        changesContentOpacityWhenHighlighted = true
    }
}

private extension GameVideoFooterView {
    enum Constants {
        static let progressTransitionOffset = CGFloat(72)
        static let progressTransitionDuration = TimeInterval(0.25)
    }

    func setupLayout() {
        addSubview(textLabel)
        textLabel.snp.makeConstraints {
            $0.leading.trailing.top.equalToSuperview().inset(24)
        }

        addSubview(tutorialButton)
        tutorialButton.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(24)
            $0.bottom.equalTo(safeAreaLayoutGuide.snp.bottom).inset(16)
            $0.height.equalTo(56)
        }

        addSubview(progressView)
        progressView.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(24)
            $0.bottom.equalTo(safeAreaLayoutGuide.snp.bottom).inset(16)
            $0.height.equalTo(56)
        }
    }

    func applyWaitingState() {
        textLabel.isHidden = true
        tutorialButton.isHidden = false
        setupProgressViews(as: .hidden)
    }

    func applySubroundStartState() {
        textLabel.isHidden = false
        textLabel.text = String(localized: .Game.gameVideoRoundStarting)
        tutorialButton.isHidden = true
        setupProgressViews(as: .hidden)
    }

    func applyHostingState(viewModel: GameVideoViewLayout.ViewModel) {
        textLabel.isHidden = true
        textLabel.text = nil
        tutorialButton.isHidden = true
        progressView.bind(viewModel: viewModel)
        setupProgressViews(as: .progressView)
    }

    func setupAsHidden() {
        textLabel.isHidden = true
        textLabel.text = nil
        tutorialButton.isHidden = true
        setupProgressViews(as: .hidden)
    }

    private func setupProgressViews(as state: ProgressState) {
        guard progressState != state else {
            return
        }

        progressState = state

        switch state {
        case .hidden:
            setProgressViewVisible(false)
        case .progressView:
            setProgressViewVisible(true)
        }
    }

    func setProgressViewVisible(_ isVisible: Bool) {
        progressView.layer.removeAllAnimations()

        if isVisible {
            progressView.isHidden = false
        }

        UIView.animate(
            withDuration: Constants.progressTransitionDuration,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut],
            animations: { [self] in
                progressView.alpha = isVisible ? 1 : 0
                progressView.transform = isVisible ? .identity : hiddenProgressTransform
            },
            completion: { [self] _ in
                switch progressState {
                case .progressView:
                    progressView.alpha = 1
                    progressView.isHidden = false
                    progressView.transform = .identity
                case .hidden:
                    progressView.isHidden = true
                }
            }
        )
    }

    var hiddenProgressTransform: CGAffineTransform {
        CGAffineTransform(translationX: 0, y: Constants.progressTransitionOffset)
    }
}

private extension GameVideoFooterView {
    final class ProgressView: UIView {
        private let progressModel = FooterProgressModel()
        private lazy var hostingController = UIHostingController(
            rootView: FooterProgressBarsView(model: progressModel)
        )

        override init(frame: CGRect) {
            super.init(frame: frame)
            setupLayout()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func setupLayout() {
            guard let hostedView = hostingController.view else {
                return
            }

            hostedView.backgroundColor = .clear

            addSubview(hostedView)
            hostedView.snp.makeConstraints {
                $0.edges.equalToSuperview()
            }
        }

        func bind(viewModel: GameVideoViewLayout.ViewModel) {
            progressModel.bind(viewModel: viewModel)
        }
    }
}

@Observable
private final class FooterProgressModel {
    private(set) var subroundsCount = 0
    private(set) var currentIndex = 0
    private(set) var currentProgress = CGFloat(0)

    func bind(viewModel: GameVideoViewLayout.ViewModel) {
        subroundsCount = viewModel.subroundsCount
        currentIndex = viewModel.currentSubroundCount - 1
        currentProgress = viewModel.timerInfo.progress.clamped(to: 0 ... 1)
    }

    func progress(forIndex index: Int) -> CGFloat {
        if index < currentIndex {
            1
        } else if index == currentIndex {
            currentProgress
        } else {
            0
        }
    }
}

private struct FooterProgressBarsView: View {
    var model: FooterProgressModel

    var body: some View {
        HStack(spacing: .zero) {
            ForEach(0 ..< model.subroundsCount, id: \.self) { index in
                progressBar(at: index)
                    .frame(
                        width: 16,
                        height: 56
                    )
                if index < model.subroundsCount - 1 {
                    Spacer(minLength: 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func progressBar(at index: Int) -> some View {
        progressBar(model.progress(forIndex: index))
            .animation(
                index == model.currentIndex ? .linear(duration: 1) : nil,
                value: model.currentProgress
            )
    }

    func progressBar(_ progress: CGFloat) -> some View {
        ZStack {
            Capsule()
                .fill(.dim2RoundProgressTrack)

            FooterProgressFillShape(progress: progress)
                .fill(.dim2RoundProgressFill)
        }
        .clipShape(Capsule())
    }
}

private struct FooterProgressFillShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let progress = progress.clamped(to: 0 ... 1)
        let fillHeight = rect.height * progress
        let fillRect = CGRect(
            x: rect.minX,
            y: rect.maxY - fillHeight,
            width: rect.width,
            height: fillHeight
        )

        return Path(fillRect)
    }
}
