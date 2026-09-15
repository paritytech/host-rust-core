import Foundation
import UIKit
import SubstrateSdk
import Individuality

@MainActor
final class TattooListWireframe: TattooListWireframeProtocol {
    let state: ProofOfInkFlowStateProtocol

    init(state: ProofOfInkFlowStateProtocol) {
        self.state = state
    }

    func showTattooCollection(
        from view: TattooListViewProtocol?,
        sectionMetadata: TattooSectionMetadata,
        collections: [ProofOfInk.Collection],
        tattooParams: TattooGenerationParams
    ) {
        guard let tattooFamily = TattooFamilyDetailsViewFactory.createView(
            for: state,
            sectionMetadata: sectionMetadata,
            tattooFamilies: collections,
            tattooParams: tattooParams
        ) else {
            return
        }

        view?.controller.navigationController?.pushViewController(
            tattooFamily.controller,
            animated: true
        )
    }

    func showDeposit(from _: TattooListViewProtocol?, neededAmount _: Balance) -> UIViewController? {
        nil
//        guard let depositView = DepositViewFactory.createView(type: .tattoo, for: neededAmount, onClose: nil) else {
//            return nil
//        }
//
//        let navigationController = AppNavigationController(rootViewController: depositView.controller)
//        navigationController.modalPresentationStyle = .fullScreen
//
//        view?.controller.present(navigationController, animated: true)
//
//        return navigationController
    }

    func showExitConfirmation(from view: TattooListViewProtocol?, model: DiscardDIMModel) -> DiscardDIMViewProtocol? {
        guard let controller = view?.controller else { return nil }
        let view = DiscardDIMViewFactory.createView(
            for: model,
            discardDIMViewModelMaker: DiscardTattooViewModelFactory()
        )
        controller.present(view.controller, animated: true)
        return view
    }

    func dismiss(from view: TattooListViewProtocol?) {
        view?.controller.dismiss(animated: true)
    }
}
