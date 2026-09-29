import UIKitExt

protocol DiscardDIMViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: DiscardDIMViewModel)
    func didReceive(activity active: Bool)
}

@MainActor
protocol DiscardDIMPresenterProtocol: AnyObject {
    func setup()
    func cancel()
    func discardReservation()
}

@MainActor
protocol DiscardDIMWireframeProtocol: AnyObject {
    func close(view: DiscardDIMViewProtocol?, completion: (() -> Void)?)
}
