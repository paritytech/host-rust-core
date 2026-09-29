import SwiftUI
import PolkadotUI

final class ChatWithPlayersViewController: UIHostingController<ChatWithPlayersView>, RootScreen {
    let presenter: ChatWithPlayersPresenterProtocol

    init(presenter: ChatWithPlayersPresenterProtocol) {
        self.presenter = presenter
        super.init(rootView: ChatWithPlayersView())
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupHandlers()
        presenter.setup()
        rootView.viewModel.action = { [weak presenter] in
            presenter?.didSelectPlayer($0)
        }
    }

    private func setupHandlers() {}
}

extension ChatWithPlayersViewController: ChatWithPlayersViewProtocol {
    func didReceive(viewModel: [Player]) {
        rootView.viewModel.players = viewModel
    }
}
