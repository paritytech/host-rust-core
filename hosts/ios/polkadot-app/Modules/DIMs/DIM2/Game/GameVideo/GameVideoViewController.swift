import UIKit
import DesignSystem
import SubstrateSdk
import FoundationExt

final class GameVideoViewController: UIViewController, ViewHolder {
    typealias RootViewType = GameVideoViewLayout

    let presenter: GameVideoPresenterProtocol

    init(presenter: GameVideoPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = GameVideoViewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        traitOverrides.appTheme = ThemesRegistry.default
        addHandlers()
        presenter.setup()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presenter.onAppear()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        presenter.onDisappear()
    }
}

extension GameVideoViewController: HiddableBarWhenPushed {}

extension GameVideoViewController: GameVideoViewProtocol {
    func didReceive(
        viewModel: GameVideoViewLayout.ViewModel,
        rendererManager: RTCRendererManaging,
        playerVoteHandler: @escaping PlayerVoteAction,
        playerBanAction: @escaping PlayerBanAction
    ) {
        rootView.bind(
            viewModel: viewModel,
            rendererManager: rendererManager,
            playerVoteHandler: playerVoteHandler,
            playerBanAction: playerBanAction
        )
    }

    func requestPreview(for player: AccountId) -> UIImage? {
        rootView.requestPreview(for: player)
    }
}

private extension GameVideoViewController {
    func addHandlers() {
        rootView.closeButton.addTarget(
            self,
            action: #selector(actionClose),
            for: .touchUpInside
        )

        rootView.tutorialButton.addTarget(
            self,
            action: #selector(actionTutorial),
            for: .touchUpInside
        )

        rootView.onTooltipDismissed = { [weak self] tooltipType in
            self?.presenter.didDismissTooltip(tooltipType)
        }
    }

    @objc
    func actionClose() {
        presenter.close()
    }

    @objc
    func actionTutorial() {
        presenter.showTutorial()
    }
}
