import Foundation
import Individuality
import ChainRegistry

@MainActor
enum TattooFamilyDetailsViewFactory {
    static func createView(
        for state: ProofOfInkFlowStateProtocol,
        sectionMetadata: TattooSectionMetadata,
        tattooFamilies: [ProofOfInk.Collection],
        tattooParams: TattooGenerationParams
    ) -> TattooFamilyDetailsViewProtocol? {
        guard let interactor = createInteractor(for: tattooFamilies)
        else {
            return nil
        }

        let wireframe = TattooFamilyDetailsWireframe(state: state)

        let presenter = TattooFamilyDetailsPresenter(
            sectionMetadata: sectionMetadata,
            tattooFamilies: tattooFamilies,
            interactor: interactor,
            wireframe: wireframe,
            tattooParams: tattooParams,
            viewModelFactory: TattooFamilyViewModelFactory(userInkChoiceProvider: UserInkChoiceProvider())
        )

        let view = TattooFamilyDetailsViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }

    private static func createInteractor(
        for tattooFamilies: [ProofOfInk.Collection]
    ) -> TattooFamilyDetailsInteractor? {
        let chainRegistry = ChainRegistryFacade.sharedRegistry

        guard
            let connection = chainRegistry.getConnection(for: AppConfig.Chains.usernameChain),
            let runtimeProvider = chainRegistry.getRuntimeProvider(for: AppConfig.Chains.usernameChain) else {
            return nil
        }

        let operationQueue = OperationManagerFacade.sharedDefaultQueue

        return .init(
            families: tattooFamilies,
            connection: connection,
            runtimeProvider: runtimeProvider,
            proofOfInkFactory: ProofOfInkOperationFactory(operationQueue: operationQueue),
            jsonLocalSubscriptionFactory: JsonDataProviderFactory.shared,
            operationQueue: operationQueue
        )
    }
}
