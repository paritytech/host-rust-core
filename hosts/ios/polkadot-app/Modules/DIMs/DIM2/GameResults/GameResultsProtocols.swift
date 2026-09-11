import Foundation
import UIKitExt

@MainActor
protocol GameResultsViewProtocol: ControllerBackedProtocol {
    func deliverInput(_ input: GameResultsInput)
    func deliverOutcome(_ outcome: GameOutcome)
    func deliverDisplayName(_ name: String)
    func deliverUsernameAvailability(
        _ availability: GameResultsInput.UsernameClaim.Availability,
        alternatives: [String]?
    )
    func pushAttestation(index: Int, hash: String, highValue: Bool?)
}

@MainActor
protocol GameResultsPresenterProtocol: AnyObject {
    func setup()
}

@MainActor
protocol GameResultsInteractorInputProtocol: AnyObject {
    func start(context: ReportSuccessContext)
    func stop()
    func resolveUsernameAvailability(name: String) async -> GameResultsInput.UsernameClaim.Availability
    func submitClaim()
}

@MainActor
protocol GameResultsInteractorOutputProtocol: AnyObject {
    func didReceiveResults(_ input: GameResultsInput)
    func didReceiveOutcome(_ outcome: GameOutcome)
    func didReceiveAttestation(hash: Data)
}

@MainActor
protocol GameResultsWireframeProtocol: AnyObject {
    func close(view: GameResultsViewProtocol?)
}

@MainActor
protocol AttestationSink: AnyObject {
    func push(hash: Data)
    func close()
}
