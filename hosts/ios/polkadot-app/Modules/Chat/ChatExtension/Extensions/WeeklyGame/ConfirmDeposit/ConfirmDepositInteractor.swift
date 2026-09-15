import Foundation
import SubstrateSdk
import KeyDerivation
import ChainRegistry
import StructuredConcurrency

final class ConfirmDepositInteractor {
    weak var presenter: ConfirmDepositInteractorOutputProtocol?

    #if TESTNET_FEATURE
        private let topUpService: TopUpService? = TopUpService.create(for: AppConfig.Assets.dimAsset)
        private var topUpTask: Task<Void, Error>?
    #endif

    private let logger: LoggerProtocol
    private let chainAsset: ChainAsset
    private let candidateWallet: WalletManaging

    init(
        candidateWallet: WalletManaging,
        chainAsset: ChainAsset,
        logger: LoggerProtocol
    ) {
        self.candidateWallet = candidateWallet
        self.chainAsset = chainAsset
        self.logger = logger
    }

    #if TESTNET_FEATURE
        deinit {
            topUpTask?.cancel()
        }
    #endif
}

extension ConfirmDepositInteractor: ConfirmDepositInteractorInputProtocol {
    func setup() {}

    func didTapConfirm(amount: Balance) {
        #if TESTNET_FEATURE
            guard let topUpService else {
                return
            }
            MainActor.assumeIsolated {
                presenter?.didStartDeposit()
            }

            topUpTask?.cancel()
            topUpTask = Task { @MainActor [weak presenter, logger, candidateWallet] in
                do {
                    try await markStallActivity("Deposit") {
                        try await topUpService.topUp(
                            candidateWallet,
                            amount: .plank(amount)
                        )
                    }
                    presenter?.didFinishDeposit()
                } catch {
                    logger.error("Top up failed: \(error)")
                    presenter?.didFailDeposit(error)
                }
            }
        #else
            // No-op for non-testnet
        #endif
    }
}
