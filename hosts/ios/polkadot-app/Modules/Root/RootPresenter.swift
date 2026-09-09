import UIKit

@MainActor
final class RootPresenter {
    weak var view: RootViewProtocol?
    let wireframe: RootWireframeProtocol
    let interactor: RootInteractorInputProtocol
    let viewModelFactory: RootInitViewModelMaking

    private var onComplete: (() -> Void)?

    init(
        wireframe: RootWireframeProtocol,
        interactor: RootInteractorInputProtocol,
        viewModelFactory: RootInitViewModelMaking
    ) {
        self.wireframe = wireframe
        self.interactor = interactor
        self.viewModelFactory = viewModelFactory
    }
}

extension RootPresenter: RootPresenterProtocol {
    func loadOnLaunch(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete

        view?.didReceive(viewModel: viewModelFactory.makeInitial())
        interactor.setup()
    }
}

extension RootPresenter: RootInteractorOutputProtocol {
    func didDecide(destination: RootDestination) {
        show(destination)

        onComplete?()
        onComplete = nil
    }

    func didExceedSetupTimeout() {
        view?.didReceive(viewModel: viewModelFactory.makeWaitingForNetwork())
    }

    #if TESTNET_FEATURE
        func didRequireAppFactoryReset() {
            wireframe.showAppFactoryResetSheet()
        }
    #endif
}

private extension RootPresenter {
    func show(_ destination: RootDestination) {
        switch destination {
        case .selectTheme:
            wireframe.showThemeSelection(with: self)
        case .onboarding:
            wireframe.showOnboarding(with: self)
        case .restoreFromCloud:
            wireframe.showRestoreFromCloud(with: self)
        case .usernameCheck:
            wireframe.showUsernameCheck(with: self)
        case .dashboard:
            wireframe.showDashboard()
        case .jailbroken:
            wireframe.showJailbroken()
        case .broken:
            wireframe.showBroken()
        }
    }
}

extension RootPresenter: RootStateObserving {
    func didCreateWallets() {
        interactor.completeWalletsCreation()
    }

    func didRestoreWallets() {
        interactor.completeWalletsRecovery()
    }

    func didDecideBroken() {
        show(.broken)
    }

    func didClaimUsername() {
        interactor.reevaluate()
    }

    func didDecideClaim() {
        wireframe.showUsernameClaim(with: self)
    }

    func didSelectTheme() {
        interactor.reevaluate()
    }
}
