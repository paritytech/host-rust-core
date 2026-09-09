import Foundation

@MainActor
final class EnableNotificationsPresenter {
    weak var view: EnableNotificationsViewProtocol?

    let wireframe: EnableNotificationsWireframeProtocol
    let interactor: EnableNotificationsInteractorInputProtocol
    let viewModelFactory: EnableNotificationViewModelMaking
    let model: EnableNotificationsModel
    let variant: EnableNotificationsVariant

    init(
        wireframe: EnableNotificationsWireframeProtocol,
        interactor: EnableNotificationsInteractorInputProtocol,
        viewModelFactory: EnableNotificationViewModelMaking,
        model: EnableNotificationsModel,
        variant: EnableNotificationsVariant
    ) {
        self.wireframe = wireframe
        self.interactor = interactor
        self.viewModelFactory = viewModelFactory
        self.model = model
        self.variant = variant
    }
}

extension EnableNotificationsPresenter: EnableNotificationsPresenterProtocol {
    func setup() {
        interactor.setup()
    }

    func enableNotifications() {
        interactor.requestNotificationsAccess()
    }

    func discardNotifications() {
        let enableAction: (() -> Void) = { [weak self] in
            self?.interactor.requestNotificationsAccess()
        }

        let discardAction: (() -> Void) = { [weak self] in
            self?.interactor.confirmDiscardNotifications()
        }

        let model = DiscardNotificationsModel(
            onEnableNotifications: enableAction,
            onDiscardNotifications: discardAction
        )

        wireframe.confirmDiscard(
            on: view,
            with: model,
            viewModelFactory: DiscardNotificationsViewModelFactory(
                variant: variant
            )
        )
    }
}

extension EnableNotificationsPresenter: EnableNotificationsInteractorOutputProtocol {
    func didReceive(status: NotificationAccessStatus) {
        switch status {
        case .allowed:
            model.resultHandler(view, true)
        case let .notAllowed(denied):
            provideViewModel(isDenied: denied)
        }
    }

    func didReceive(accessGranted: Bool) {
        model.resultHandler(view, accessGranted)
    }

    func didReceiveGoToSettings() {
        wireframe.openApplicationSettings()
    }
}

private extension EnableNotificationsPresenter {
    func provideViewModel(isDenied: Bool) {
        let viewModel = viewModelFactory.viewModel(isDenied: isDenied)
        view?.didReceive(reasonsViewModel: viewModel)
    }
}
