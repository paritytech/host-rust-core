import UIKit

@MainActor
protocol RootViewProtocol: AnyObject {
    func didReceive(viewModel: RootInitViewLayout.ViewModel)
}

@MainActor
protocol RootPresenterProtocol: AnyObject {
    func loadOnLaunch(onComplete: @escaping () -> Void)
}

@MainActor
protocol RootWireframeProtocol: AnyObject {
    func showDashboard()
    func showOnboarding(with observer: RootStateObserving)
    func showRestoreFromCloud(with observer: RootStateObserving)
    func showUsernameCheck(with observer: RootStateObserving)
    func showUsernameClaim(with observer: RootStateObserving)
    func showThemeSelection(with observer: RootStateObserving)
    func showBroken()
    func showJailbroken()
    #if TESTNET_FEATURE
        func showAppFactoryResetSheet()
    #endif
}

@MainActor
protocol RootInteractorInputProtocol: AnyObject {
    func setup()
    func reevaluate()
    func completeWalletsCreation()
    func completeWalletsRecovery()
}

@MainActor
protocol RootInteractorOutputProtocol: AnyObject {
    func didDecide(destination: RootDestination)
    func didExceedSetupTimeout()
    #if TESTNET_FEATURE
        func didRequireAppFactoryReset()
    #endif
}

@MainActor
protocol RootPresenterFactoryProtocol {
    static func createPresenter(
        with window: UIWindow
    ) -> RootPresenterProtocol
}
