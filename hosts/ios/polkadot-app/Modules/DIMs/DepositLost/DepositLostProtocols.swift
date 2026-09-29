import UIKitExt

protocol DepositLostViewProtocol: AnyObject, ControllerBackedProtocol {
    func didReceive(viewModel: DepositLostViewLayout.ViewModel)
}

@MainActor
protocol DepositLostPresenterProtocol: AnyObject {
    func setup()
}
