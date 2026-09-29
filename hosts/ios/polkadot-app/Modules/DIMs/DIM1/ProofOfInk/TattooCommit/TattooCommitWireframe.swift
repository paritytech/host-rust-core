import Foundation

@MainActor
final class TattooCommitWireframe: TattooCommitWireframeProtocol {
    let state: ProofOfInkFlowStateProtocol

    init(state: ProofOfInkFlowStateProtocol) {
        self.state = state
    }

    func confirm(on view: TattooCommitViewProtocol?, model: TattooConfirmModel) {
        guard let confirmView = TattooConfirmViewFactory.createView(for: model) else {
            return
        }

        view?.controller.present(confirmView.controller, animated: true)
    }

    func cancel(view: TattooCommitViewProtocol?) {
        view?.controller.navigationController?.popViewController(animated: true)
    }

    func complete(view: TattooCommitViewProtocol?) {
        view?.controller.navigationController?.dismiss(animated: true)
    }
}
