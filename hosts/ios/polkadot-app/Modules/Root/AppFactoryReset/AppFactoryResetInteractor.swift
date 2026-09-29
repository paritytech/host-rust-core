#if TESTNET_FEATURE
    import Foundation

    final class AppFactoryResetInteractor {
        weak var presenter: AppFactoryResetInteractorOutputProtocol?

        private let resetService: AppFactoryResetService

        init(resetService: AppFactoryResetService) {
            self.resetService = resetService
        }
    }

    extension AppFactoryResetInteractor: AppFactoryResetInteractorInputProtocol {
        func performReset() {
            resetService.resetAllData()
            MainActor.assumeIsolated {
                presenter?.didCompleteReset()
            }
        }
    }
#endif
