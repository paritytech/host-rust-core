import Individuality
import UIKitExt

protocol TattooFamilyDetailsViewProtocol: ControllerBackedProtocol {
    func didReceive(_ viewModel: TattooFamilyDetailsViewModel)
}

@MainActor
protocol TattooFamilyDetailsPresenterProtocol: AnyObject {
    func setup()
    func perform(_ action: TattooFamilyDetailsAction)
    func updateOnAppear()
}

protocol TattooFamilyDetailsInteractorInputProtocol: AnyObject {
    func setup()
    func retryReserved()
}

@MainActor
protocol TattooFamilyDetailsInteractorOutputProtocol: AnyObject {
    func didReceiveReservedDesigns(_ reservedDesigns: ProofOfInkPallet.ReservedDesignsResult)
    func didReceiveError(_ error: TattooFamilyDetailsInteractorError)
}

@MainActor
protocol TattooFamilyDetailsWireframeProtocol: AlertPresentable, ErrorPresentable, CommonRetryable {
    func showTattooCommit(from view: TattooFamilyDetailsViewProtocol?, choice: ProofOfInk.Choice)
}

enum TattooFamilyDetailsInteractorError {
    case reservedFailed(Error)
}
