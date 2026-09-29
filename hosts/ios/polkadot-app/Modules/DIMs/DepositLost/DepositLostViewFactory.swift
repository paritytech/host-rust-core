import Foundation

@MainActor
enum DepositLostViewFactory {
    static func createView() -> DepositLostViewProtocol? {
        let presenter = DepositLostPresenter(
            viewModelFactory: DepositLostViewModelFactory()
        )
        let view = DepositLostViewController(presenter: presenter)
        presenter.view = view
        return view
    }
}
