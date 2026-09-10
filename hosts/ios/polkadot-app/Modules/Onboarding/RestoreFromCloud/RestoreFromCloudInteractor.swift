import UIKit
import Operation_iOS

final class RestoreFromCloudInteractor {
    weak var presenter: RestoreFromCloudInteractorOutputProtocol?

    private let walletSetupManager: WalletSetupManaging
    private let operationQueue: OperationQueue
    private let logger: LoggerProtocol

    private let cancellable = CancellableCallStore()
    private var authState = AuthorizationState.notAuthorized

    init(
        walletSetupManager: WalletSetupManaging,
        operationQueue: OperationQueue,
        logger: LoggerProtocol
    ) {
        self.walletSetupManager = walletSetupManager
        self.operationQueue = operationQueue
        self.logger = logger
    }
}

extension RestoreFromCloudInteractor: RestoreFromCloudInteractorInputProtocol {
    func restoreWallets() {
        performRestoreWallets()
    }
}

private extension RestoreFromCloudInteractor {
    enum AuthorizationState {
        case notAuthorized
        case inProgress
        case done
    }

    func performRestoreWallets() {
        guard authState == .notAuthorized else {
            return
        }

        guard !cancellable.hasCall else {
            logger.warning("Already restoring wallets")
            return
        }

        authState = .inProgress
        MainActor.assumeIsolated {
            presenter?.didReceiveInProgress(true)

            presenter?.authorizeUser { [weak self] isAuthorized in
                if isAuthorized {
                    self?.authState = .done
                    self?.continueRestoreWallets()
                } else {
                    self?.authState = .notAuthorized
                }
            }
        }
    }

    func continueRestoreWallets() {
        do {
            try walletSetupManager.restoreWallets()
            MainActor.assumeIsolated {
                presenter?.didRestoreWallets()
            }
        } catch {
            MainActor.assumeIsolated {
                presenter?.didDecideBroken()
            }
            logger.error("Unexpected wallet restore error: \(error)")
        }
    }
}
