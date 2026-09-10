import UIKitExt

protocol TattooConfirmViewProtocol: ControllerBackedProtocol {}

@MainActor
protocol TattooConfirmPresenterProtocol: AnyObject {
    func cancel()
    func confirm()
}

@MainActor
protocol TattooConfirmWireframeProtocol: AnyObject {
    func close(view: TattooConfirmViewProtocol?, completion: (() -> Void)?)
}
