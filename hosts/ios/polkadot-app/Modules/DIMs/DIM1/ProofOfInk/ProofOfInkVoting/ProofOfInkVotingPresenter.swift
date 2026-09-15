import Foundation
import PolkadotUI

@MainActor
final class ProofOfInkVotingPresenter {
    weak var view: ProofOfInkVotingViewProtocol?

    let wireframe: ProofOfInkVotingWireframeProtocol
    let interactor: ProofOfInkVotingInteractorInputProtocol
    let viewModelProvider: ProofOfInkVotingViewModelProviding?
    let model: ProofOfInkVotingModel

    init(
        interactor: ProofOfInkVotingInteractorInputProtocol,
        wireframe: ProofOfInkVotingWireframeProtocol,
        viewModelProvider: ProofOfInkVotingViewModelProviding?,
        model: ProofOfInkVotingModel
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.viewModelProvider = viewModelProvider
        self.model = model
    }
}

// MARK: - ProofOfInkVotingPresenterProtocol

extension ProofOfInkVotingPresenter: ProofOfInkVotingPresenterProtocol {
    func setup() {
        interactor.setup()
        provideViewModel()
    }

    func close() {
        wireframe.close(view: view)
    }

    func report() {
        wireframe.showReport(from: view)
    }

    func vote(result: ProofOfInkVotingLayout.VoteResult) {
        wireframe.close(view: view)

        switch result {
        case .positive:
            model.onVoting?(true)
        case .negative:
            model.onVoting?(false)
        }
    }
}

// MARK: - ProofOfInkVotingInteractorOutputProtocol

extension ProofOfInkVotingPresenter: ProofOfInkVotingInteractorOutputProtocol {}

// MARK: - Private

private extension ProofOfInkVotingPresenter {
    func provideViewModel() {
        guard let viewModelProvider else {
            return
        }
        let viewModel = viewModelProvider.provideModel()
        view?.didReceive(viewModel: viewModel)
    }
}
