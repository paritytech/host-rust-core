import Foundation
import Keystore_iOS

@MainActor
enum EnableNotificationsViewFactory {
    static func createView(
        model: EnableNotificationsModel,
        localNotificationService: UserNotificationServicing,
        variant: EnableNotificationsVariant,
    ) -> EnableNotificationsViewProtocol {
        let interactor = EnableNotificationsInteractor(
            notificationCenter: .default,
            localNotificationService: localNotificationService
        )
        let wireframe = EnableNotificationsWireframe()
        let presenter = EnableNotificationsPresenter(
            wireframe: wireframe,
            interactor: interactor,
            viewModelFactory: EnableNotificationViewModelFactory(variant: variant),
            model: model,
            variant: variant
        )
        let view = EnableNotificationsViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
