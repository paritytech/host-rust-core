import Foundation

final class DepositLostPresenter {
    weak var view: DepositLostViewProtocol?
    let viewModelFactory: DepositLostViewModelMaking

    init(
        viewModelFactory: DepositLostViewModelMaking
    ) {
        self.viewModelFactory = viewModelFactory
    }
}

extension DepositLostPresenter: DepositLostPresenterProtocol {
    func setup() {
        provideViewModel()
    }
}

extension DepositLostPresenter {
    func provideViewModel() {
        let viewModel = viewModelFactory.make()
        view?.didReceive(viewModel: viewModel)
    }
}
