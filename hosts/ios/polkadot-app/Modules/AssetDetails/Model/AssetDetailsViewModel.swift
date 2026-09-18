import Observation
import PolkadotUI
import Combine
import SubstrateSdk
import Foundation

struct CoinageBalanceBreakdownViewModel {
    /// Bare amounts, no symbol: the headline carries ``symbol`` once, in small type, and the
    /// three figures below it are read against that.
    let totalBalance: String
    let availableNowBalance: String
    let gainingPrivacyBalance: String
    let pendingBalance: String
    let symbol: String
    let composition: CoinageCompositionBar.Model
    /// Coins and vouchers in one list, already ordered for display.
    let holdings: [CoinageHoldingViewModel]
}

/// A single coin or voucher row: its value, and a number-free status depiction.
struct CoinageHoldingViewModel: Identifiable {
    let id: String
    /// The bare value, no currency symbol. Nil until the denomination context is known.
    let amount: String?
    let status: Status

    enum Status: Equatable {
        case coin(CoinStatusView.Model)
        case voucher(VoucherStatusView.Model)
    }
}

protocol AssetDetailsViewModelProtocol: Observation.Observable {
    var balanceCardModel: AssetDetailsBalanceCard.ViewModel? { get set }
    var showsBackupNotification: Bool { get set }
    var fundingStates: [AssetFundingStatusView.FundingState] { get set }
    var isFundingExpanded: Bool { get set }
    var isUpdating: Bool { get set }

    var onAddMoney: (() -> Void)? { get set }
    var onSendMoney: (() -> Void)? { get set }
    var onFundingCompleted: (() -> Void)? { get set }
    var onFundingFailed: (() -> Void)? { get set }
    var onBackupSync: (() -> Void)? { get set }
    var onBackupCancel: (() -> Void)? { get set }
    var onBackupWhyUpdate: (() -> Void)? { get set }

    var isTopUpInProgress: Bool { get set }
    var onTopUp: (() -> Void)? { get set }
    var isWithdrawInProgress: Bool { get set }
    var onWithdraw: (() -> Void)? { get set }

    var coinageBreakdown: CoinageBalanceBreakdownViewModel? { get set }
    /// Set only in builds that carry the debug affordances; nil elsewhere, which is what hides the
    /// button rather than a second conditional in the view.
    var onMakeAllVouchersReady: (() -> Void)? { get set }
    #if TESTNET_FEATURE
        var isTestnetTopUpInProgress: Bool { get set }
        var onTestnetTopUp: (() -> Void)? { get set }
    #endif
}

@Observable
class AssetDetailsViewModel: AssetDetailsViewModelProtocol {
    var balanceCardModel: AssetDetailsBalanceCard.ViewModel?
    var showsBackupNotification: Bool = false
    var fundingStates: [AssetFundingStatusView.FundingState] = []
    var isFundingExpanded: Bool = false
    var isUpdating: Bool = false

    var onAddMoney: (() -> Void)?
    var onSendMoney: (() -> Void)?
    var onFundingCompleted: (() -> Void)?
    var onFundingFailed: (() -> Void)?
    var onBackupSync: (() -> Void)?
    var onBackupCancel: (() -> Void)?
    var onBackupWhyUpdate: (() -> Void)?

    var isTopUpInProgress: Bool = false
    var onTopUp: (() -> Void)?
    var isWithdrawInProgress: Bool = false
    var onWithdraw: (() -> Void)?

    var coinageBreakdown: CoinageBalanceBreakdownViewModel?
    var onMakeAllVouchersReady: (() -> Void)?
    #if TESTNET_FEATURE
        var isTestnetTopUpInProgress: Bool = false
        var onTestnetTopUp: (() -> Void)?
    #endif
}
