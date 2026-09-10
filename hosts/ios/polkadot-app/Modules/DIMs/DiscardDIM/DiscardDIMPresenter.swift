import Foundation
import Foundation_iOS

final class DiscardDIMPresenter {
    weak var view: DiscardDIMViewProtocol?
    let wireframe: DiscardDIMWireframeProtocol
    let model: DiscardDIMModel
    let viewModelMaker: DiscardDIMViewModelMaking

    init(
        model: DiscardDIMModel,
        wireframe: DiscardDIMWireframeProtocol,
        viewModelMaker: DiscardDIMViewModelMaking
    ) {
        self.model = model
        self.wireframe = wireframe
        self.viewModelMaker = viewModelMaker
    }
}

private extension DiscardDIMPresenter {
    func provideViewModel() {
        let viewModel = viewModelMaker.makeVieModel()
        view?.didReceive(viewModel: viewModel)
    }
}

extension DiscardDIMPresenter: DiscardDIMPresenterProtocol {
    func setup() {
        provideViewModel()
    }

    func cancel() {
        model.cancelClosure()
    }

    func discardReservation() {
        model.discardClosure()
    }
}

extension DiscardDIMPresenter: @MainActor Localizable {
    @MainActor func applyLocalization() {
        guard let view, view.isSetup else { return }
        provideViewModel()
    }
}
