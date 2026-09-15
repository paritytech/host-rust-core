import UIKitExt

protocol BalanceInfoViewProtocol: ControllerBackedProtocol {
    func didReceive(model: BalanceInfoModel)
}

@MainActor
protocol BalanceInfoPresenterProtocol: AnyObject {
    func setup()
    func onAvailableNowInfo()
    func onAvailableSoonInfo()
}

@MainActor
protocol BalanceInfoWireframeProtocol: AnyObject {
    func showAvailableNowInfo(from view: ControllerBackedProtocol?)
    func showAvailableSoonInfo(from view: ControllerBackedProtocol?)
}
