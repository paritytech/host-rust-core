import UIKit
import SubstrateSdk
import Individuality
import UIKitExt

protocol TattooListViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModels: [TattooListViewModel])
    func didReceive(stateViewModel: TattooListStateViewModel, viewModel: TattooListViewLayout.ViewModel)
    func didReceive(tattooApplyActivity active: Bool)
}

@MainActor
protocol TattooListPresenterProtocol: AnyObject {
    func setup()
    func updateOnAppear()
    func selectCollection(viewModel: TattooListViewModel)
    func addDeposit()
    func presentTattooTermnationConfirmation()
    func dismissTattoo()
}

protocol TattooListInteractorInputProtocol: AnyObject {
    func setup()
    func applyForTattoo()
    func retryFamilies()
    func retryReserved()
    func retryTattooMetadata(for familyIds: [ProofOfInkPallet.FamilyId])
    func subscribeTattooMetadata(for familyIds: [ProofOfInkPallet.FamilyId])
    func retryRequiredPersonBalance()
    func exitTattoo()
    func terminateProofOfInk()
    #if TESTNET_FEATURE
        func addDeposit(amount: Balance)
    #endif
}

@MainActor
protocol TattooListInteractorOutputProtocol: AnyObject {
    func didReceiveDesignFamilies(_ families: ProofOfInkPallet.DesignFamiliesResult)
    func didReceiveReservedDesigns(_ reservedDesigns: ProofOfInkPallet.ReservedDesignsResult)
    func didReceiveTattooMetadata(_ metadata: TattooMetadata, for family: ProofOfInkPallet.FamilyId)
    func didReceiveNextPersonalId(_ personalId: ProofOfInkPallet.PersonalId)
    func didReceiveCandidate(_ candidate: ProofOfInkPallet.Candidate?)
    func didReceiveCurrentBalance(_ balance: Balance?)
    func didReceiveRequiredPersonBalance(_ balance: Balance)
    func didReceiveError(_ error: TattooListInteractorError)
    func didReceiveGeneralError(_ error: Error)
    func didReceiveTermination(inProgress: Bool)
    func didReceive(tattooApplyActivity active: Bool)
    func didReceiveTopUp(inProgress: Bool)
}

@MainActor
protocol TattooListWireframeProtocol: AlertPresentable, ErrorPresentable, CommonRetryable {
    func showTattooCollection(
        from view: TattooListViewProtocol?,
        sectionMetadata: TattooSectionMetadata,
        collections: [ProofOfInk.Collection],
        tattooParams: TattooGenerationParams
    )

    func showDeposit(from view: TattooListViewProtocol?, neededAmount: Balance) -> UIViewController?
    func showExitConfirmation(from view: TattooListViewProtocol?, model: DiscardDIMModel) -> DiscardDIMViewProtocol?
    func dismiss(from view: TattooListViewProtocol?)
}

enum TattooListInteractorError {
    case designFamiliesFailed(Error)
    case reservedFailed(Error)
    case tattooMetadataFailed(Error)
    case requiredPersonBalance(Error)
}
