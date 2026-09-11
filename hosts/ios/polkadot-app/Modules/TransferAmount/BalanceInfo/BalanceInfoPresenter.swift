@MainActor
final class BalanceInfoPresenter: BalanceInfoPresenterProtocol {
    weak var view: BalanceInfoViewProtocol?
    let wireframe: BalanceInfoWireframeProtocol
    let model: BalanceInfoModel

    init(
        model: BalanceInfoModel,
        wireframe: BalanceInfoWireframeProtocol
    ) {
        self.model = model
        self.wireframe = wireframe
    }

    func setup() {
        view?.didReceive(model: model)
    }

    func onAvailableNowInfo() {
        wireframe.showAvailableNowInfo(from: view)
    }

    func onAvailableSoonInfo() {
        wireframe.showAvailableSoonInfo(from: view)
    }
}
