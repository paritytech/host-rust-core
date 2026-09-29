#if TESTNET_FEATURE
    import UIKit

    final class AppFactoryResetWireframe {}

    extension AppFactoryResetWireframe: AppFactoryResetWireframeProtocol {
        func navigateToFreshStart() {
            guard
                let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                let sceneDelegate = scene.delegate as? SceneDelegate
            else {
                return
            }

            sceneDelegate.restartScene()
        }

        func dismiss(from view: AppFactoryResetViewProtocol?) {
            view?.controller.presentingViewController?.dismiss(animated: true)
        }
    }
#endif
