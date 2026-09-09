import Foundation

@MainActor
enum ProofOfInkVotingViewFactory {
    static func createView(
        model: ProofOfInkVotingModel
    ) -> ProofOfInkVotingViewProtocol? {
        let interactor = ProofOfInkVotingInteractor()
        let wireframe = ProofOfInkVotingWireframe()

        let provider = ProofOfInkVotingViewModelProvider(
            statement: model.statement,
            caseIdnex: model.caseIndex,
            familyId: model.familyId,
            votingAvailable: model.votingAvailable
        )

        let presenter = ProofOfInkVotingPresenter(
            interactor: interactor,
            wireframe: wireframe,
            viewModelProvider: provider,
            model: model
        )

        let view = ProofOfInkVotingViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
