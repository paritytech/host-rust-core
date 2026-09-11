import UIKit

@MainActor
final class EnableNotificationsWireframe: EnableNotificationsWireframeProtocol {
    func confirmDiscard(
        on view: EnableNotificationsViewProtocol?,
        with model: DiscardNotificationsModel,
        viewModelFactory: DiscardNotificationsViewModelMaking
    ) {
        let confirmView = DiscardNotificationsViewFactory.createView(
            model: model,
            viewModelFactory: viewModelFactory
        )
        view?.controller.present(confirmView.controller, animated: true)
    }
}
