import UIKit
import PolkadotUI
import UIKit_iOS

@MainActor
enum TransferPrivacyViewFactory {
    static func createGainingPrivacyConfirmation(
        amount: String,
        onSendAnyway: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> UIViewController {
        let wireframe = TransferPrivacyWireframe()
        let presenter = TransferPrivacyPresenter(
            model: TransferPrivacyModel(amount: amount),
            wireframe: wireframe,
            onSendAnyway: onSendAnyway,
            onCancel: onCancel
        )
        let view = TransferPrivacyViewController(presenter: presenter)
        presenter.view = view

        let nav = UINavigationController(rootViewController: view)
        BottomSheetViewFacade.setupBottomSheet(from: nav)

        return nav
    }
}
