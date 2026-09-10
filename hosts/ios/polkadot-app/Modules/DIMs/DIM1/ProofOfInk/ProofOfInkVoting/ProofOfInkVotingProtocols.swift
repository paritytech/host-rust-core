import PolkadotUI
import UIKitExt

protocol ProofOfInkVotingViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: ProofOfInkVotingViewModel)
}

@MainActor
protocol ProofOfInkVotingPresenterProtocol: AnyObject {
    func setup()
    func close()
    func report()
    func vote(result: ProofOfInkVotingLayout.VoteResult)
}

protocol ProofOfInkVotingInteractorInputProtocol: AnyObject {
    func setup()
}

@MainActor
protocol ProofOfInkVotingInteractorOutputProtocol: AnyObject {}

@MainActor
protocol ProofOfInkVotingWireframeProtocol: AnyObject {
    func close(view: ProofOfInkVotingViewProtocol?)
    func showReport(from view: ProofOfInkVotingViewProtocol?)
}
