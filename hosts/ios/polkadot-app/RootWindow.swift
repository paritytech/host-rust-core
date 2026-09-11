import DesignSystem
import UIKit

final class RootWindow: UIWindow {
    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)

        applyThemeInterfaceStyle()

        registerForTraitChanges([DSThemeTrait.self]) { (window: RootWindow, _) in
            window.applyThemeInterfaceStyle()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    #if TESTNET_FEATURE
        override func motionEnded(_ motion: UIEvent.EventSubtype, with _: UIEvent?) {
            guard motion == .motionShake else {
                return
            }
            showDebug()
        }

        func showDebug() {
            guard let debugView = DebugSettingsViewFactory.createView(
                flowStateProvider: SPAFlowStateProvider()
            ) else {
                return
            }
            let navigationController = AppNavigationController(rootViewController: debugView.controller)
            rootViewController?.present(navigationController, animated: true)
        }
    #endif
}

private extension RootWindow {
    func applyThemeInterfaceStyle() {
        overrideUserInterfaceStyle = UIColor.bgSurfaceMain.isLight ? .light : .dark
    }
}
