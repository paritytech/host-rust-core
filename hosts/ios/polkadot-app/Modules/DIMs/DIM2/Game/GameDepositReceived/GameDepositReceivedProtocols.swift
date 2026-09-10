import UIKitExt

protocol GameDepositReceivedViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: GameDepositReceivedViewLayout.ViewModel)
}

@MainActor
protocol GameDepositReceivedPresenterProtocol: AnyObject {
    func setup()
    func register()
    func skipRegistration()
}
