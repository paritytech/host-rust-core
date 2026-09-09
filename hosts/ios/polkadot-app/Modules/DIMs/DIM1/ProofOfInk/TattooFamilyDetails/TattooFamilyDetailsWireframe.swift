import Foundation
import Individuality

@MainActor
final class TattooFamilyDetailsWireframe: TattooFamilyDetailsWireframeProtocol {
    let state: ProofOfInkFlowStateProtocol

    init(state: ProofOfInkFlowStateProtocol) {
        self.state = state
    }

    func showTattooCommit(from view: TattooFamilyDetailsViewProtocol?, choice: ProofOfInk.Choice) {
        guard let commitView = TattooCommitViewFactory.createView(for: state, choice: choice) else {
            return
        }

        view?.controller.navigationController?.pushViewController(
            commitView.controller,
            animated: true
        )
    }
}
