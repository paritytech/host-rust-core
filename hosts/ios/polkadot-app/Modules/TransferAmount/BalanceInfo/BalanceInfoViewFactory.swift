import UIKit
import UIKit_iOS
import PolkadotUI
import DesignSystem

@MainActor
enum BalanceInfoViewFactory {
    static func createView(from model: BalanceInfoModel) -> UIViewController {
        let wireframe = BalanceInfoWireframe()
        let presenter = BalanceInfoPresenter(model: model, wireframe: wireframe)
        let view = BalanceInfoViewController(presenter: presenter)
        presenter.view = view

        let nav = UINavigationController(rootViewController: view)
        BottomSheetViewFacade.setupBottomSheet(from: nav)
        return nav
    }
}
