import UIKit
import DesignSystem
import FoundationExt

final class GameReportViewController: UIViewController, ViewHolder {
    typealias RootViewType = GameReportViewLayout

    let presenter: GameReportPresenterProtocol

    init(presenter: GameReportPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = GameReportViewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        traitOverrides.appTheme = ThemesRegistry.default
        presenter.setup()
        addHandlers()
    }
}

extension GameReportViewController: HiddableBarWhenPushed {}

extension GameReportViewController: GameReportViewProtocol {
    func didReceive(viewModel: GameReportViewLayout.ViewModel) {
        rootView.bind(viewModel: viewModel)
    }

    func didReceive(confirmButtonState: GameReportViewLayout.ConfirmButtonState) {
        rootView.bind(confirmButtonState: confirmButtonState)
    }
}

private extension GameReportViewController {
    func addHandlers() {
        rootView.didRequestToggle = { [weak self] in
            self?.presenter.toggleVote($0)
        }

        rootView.didRequestRegister = { [weak self] in
            self?.presenter.registerForNextGame()
        }

        rootView.confirmButton.addTarget(
            self,
            action: #selector(actionConfirmReport),
            for: .touchUpInside
        )
    }

    @objc
    func actionConfirmReport() {
        presenter.confirmReport()
    }
}
