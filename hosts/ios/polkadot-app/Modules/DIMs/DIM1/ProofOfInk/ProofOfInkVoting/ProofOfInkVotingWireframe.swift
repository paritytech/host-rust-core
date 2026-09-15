import Foundation

final class ProofOfInkVotingWireframe: ProofOfInkVotingWireframeProtocol {
    func close(view: ProofOfInkVotingViewProtocol?) {
        view?.controller.dismiss(animated: true)
    }

    func showReport(from _: ProofOfInkVotingViewProtocol?) {
        // TODO: implement report flow
    }
}
