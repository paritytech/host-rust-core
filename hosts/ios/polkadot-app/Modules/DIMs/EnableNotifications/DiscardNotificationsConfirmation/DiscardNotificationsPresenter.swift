import Foundation

@MainActor
final class DiscardNotificationsPresenter {
    weak var view: DiscardNotificationsViewProtocol?

    let wireframe: DiscardNotificationsWireframeProtocol
    let model: DiscardNotificationsModel
    let viewModelFactory: DiscardNotificationsViewModelMaking

    init(
        wireframe: DiscardNotificationsWireframeProtocol,
        model: DiscardNotificationsModel,
        viewModelFactory: DiscardNotificationsViewModelMaking
    ) {
        self.wireframe = wireframe
        self.viewModelFactory = viewModelFactory
        self.model = model
    }
}

extension DiscardNotificationsPresenter: DiscardNotificationsPresenterProtocol {
    func setup() {
        provideViewModel()
    }

    func enableNotifications() {
        wireframe.close(view: view) { [weak self] in
            self?.model.onEnableNotifications()
        }
    }

    func discardNotifications() {
        wireframe.close(view: view) { [weak self] in
            self?.model.onDiscardNotifications()
        }
    }
}

private extension DiscardNotificationsPresenter {
    func provideViewModel() {
        let viewModel = viewModelFactory.viewModel()
        view?.didReceive(viewModel: viewModel)
    }
}
