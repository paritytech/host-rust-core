import Foundation

@MainActor
enum GameDepositReceivedViewFactory {
    static func createView(model: GameDepositReceivedModel) -> GameDepositReceivedViewProtocol? {
        let viewFactory = GameDepositReceivedViewModelFactory(
            registrationAvailable: model.registerButtonAvailable
        )
        let presenter = GameDepositReceivedPresenter(
            model: model,
            viewModelFactory: viewFactory
        )

        let view = GameDepositReceivedViewController(presenter: presenter)

        presenter.view = view

        BottomSheetViewFacade.setupBottomSheet(from: view, preferredHeight: nil)

        return view
    }
}
