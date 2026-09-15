import Foundation

final class GameDepositReceivedPresenter {
    weak var view: GameDepositReceivedViewProtocol?
    let viewModelFactory: GameDepositReceivedViewModelMaking
    let model: GameDepositReceivedModel

    init(
        model: GameDepositReceivedModel,
        viewModelFactory: GameDepositReceivedViewModelMaking
    ) {
        self.model = model
        self.viewModelFactory = viewModelFactory
    }
}

extension GameDepositReceivedPresenter: GameDepositReceivedPresenterProtocol {
    func setup() {
        provideViewModel()
    }

    func register() {
        model.registerHandler()
    }

    func skipRegistration() {
        model.skipHandler()
    }
}

extension GameDepositReceivedPresenter {
    func provideViewModel() {
        let viewModel = viewModelFactory.viewModel()
        view?.didReceive(viewModel: viewModel)
    }
}
