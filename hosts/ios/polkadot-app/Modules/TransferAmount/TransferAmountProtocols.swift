import AsyncExtensions
import Foundation
import BigInt
import ExtrinsicService
import SubstrateSdk
import Coinage
import UIKitExt

// MARK: - View

@MainActor
protocol TransferAmountViewProtocol: ControllerBackedProtocol, ValidationResultPresentable {
    func didReceive(amountViewModel: AmountInputViewModelProtocol)
    func didReceive(assetViewModel: AssetAmountViewModel)
    func didReceive(availableBalance: String)
    /// The "Extra … is spendable at the risk of reducing your privacy" hint, or nil to hide it.
    func didReceive(privacyHint: String?)
    func didReceive(feeViewModel: BalanceViewModelProtocol?)
    func didReceive(recipient viewModel: TransferRecipientViewModel)

    func didReceive(input: String)
    func setAmountInputEnabled(_ enabled: Bool)

    func didStartSubmission()
    func didStopSubmission()

    func didStartLoading()
    func didStopLoading()

    func didReceive(transferStatus: ClaimStatus)
    func didUnlockNavigation()

    #if TESTNET_FEATURE
        func didReceive(strategyDebugInfo: TransferStrategyDebugInfo?)
    #endif
}

// MARK: - Presenter

@MainActor
protocol TransferAmountPresenterProtocol: AnyObject {
    func setup()
    func confirm()
    func onBalance()
    func onBalanceInfo()
    func changeAmount(_ newValue: Decimal?)
}

// MARK: - Interactor

protocol TransferAmountInteractorInputProtocol: AnyObject {
    var senderAddress: AccountId { get }
    var recipient: RecipientModel { get }

    func setup()
    func retrySetup()

    func lifecycleStream() -> AnyAsyncSequence<ClaimStatus>
    func previewTransfer(for amount: Decimal) async throws -> TransferPreviewValidation
    func confirmTransfer(validation: TransferPreviewValidation) async throws
    func saveRecentContact()

    #if TESTNET_FEATURE
        func previewStrategy(for amount: Decimal)
    #endif
}

@MainActor
protocol TransferAmountInteractorOutputProtocol: AnyObject {
    func didReceive(error: TransferAmountInteractorError)
    func didReceive(spendableBreakdown: TransferSpendableBreakdown)
    func didReceive(lockedBalance: Balance)

    #if TESTNET_FEATURE
        func didReceive(strategyDebugInfo: TransferStrategyDebugInfo?)
    #endif
}

@MainActor
protocol TransferAmountWireframeProtocol: TransferValidationErrorPresentable,
    AlertPresentable,
    CommonRetryable,
    ErrorPresentable,
    FeeRetryable,
    TransactionResultPresentable,
    ChatNavigating,
    CoinagePrivacyPresenting {
    func hide(view: ControllerBackedProtocol?)
    func showBalanceInfo(model: BalanceInfoModel, from view: (any ControllerBackedProtocol)?)
}

enum TransferAmountInteractorError: Error {
    case feeFailed(Error)
    case transactionFailed(Error)
    case internalError
}
