import UIKit
import DesignSystem
import FoundationExt

final class GameDepositReceivedViewController: UIViewController, ViewHolder {
    typealias RootViewType = GameDepositReceivedViewLayout

    let presenter: GameDepositReceivedPresenterProtocol

    init(presenter: GameDepositReceivedPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = GameDepositReceivedViewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        traitOverrides.appTheme = ThemesRegistry.default
        setupHandlers()
        presenter.setup()
    }
}

extension GameDepositReceivedViewController: GameDepositReceivedViewProtocol {
    func didReceive(viewModel: GameDepositReceivedViewLayout.ViewModel) {
        rootView.bind(viewModel: viewModel)
    }
}

private extension GameDepositReceivedViewController {
    func setupHandlers() {
        rootView.registerButton.addTarget(
            self,
            action: #selector(registerButtonPressed),
            for: .touchUpInside
        )

        rootView.registerLaterButton.addTarget(
            self,
            action: #selector(skipButtonPressed),
            for: .touchUpInside
        )
    }

    @objc func registerButtonPressed() {
        presenter.register()
    }

    @objc func skipButtonPressed() {
        presenter.skipRegistration()
    }
}
