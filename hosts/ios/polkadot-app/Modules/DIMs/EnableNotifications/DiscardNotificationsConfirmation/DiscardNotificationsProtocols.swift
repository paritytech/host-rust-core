import UIKitExt

protocol DiscardNotificationsViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: DiscardNotificationsViewLayout.ViewModel)
}

@MainActor
protocol DiscardNotificationsPresenterProtocol: AnyObject {
    func setup()
    func enableNotifications()
    func discardNotifications()
}

@MainActor
protocol DiscardNotificationsWireframeProtocol: AnyObject {
    func close(view: DiscardNotificationsViewProtocol?, completion: (() -> Void)?)
}
