import Foundation
import Keystore_iOS

@MainActor
enum DiscardNotificationsViewFactory {
    static func createView(
        model: DiscardNotificationsModel,
        viewModelFactory: DiscardNotificationsViewModelMaking
    ) -> DiscardNotificationsViewProtocol {
        let wireframe = DiscardNotificationsWireframe()
        let presenter = DiscardNotificationsPresenter(
            wireframe: wireframe,
            model: model,
            viewModelFactory: viewModelFactory
        )
        let view = DiscardNotificationsViewController(presenter: presenter)

        presenter.view = view

        BottomSheetViewFacade.setupBottomSheet(from: view, preferredHeight: nil)

        return view
    }
}
