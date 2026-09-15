import Observation
import PolkadotUI
import Combine
import SubstrateSdk
import Foundation

#if TESTNET_FEATURE
    struct CoinageBalanceBreakdownViewModel {
        let totalBalance: String
        let spendableBalance: String
        let pendingBalance: String
        let coinCount: Int
        let voucherCount: Int
        let coinDetails: [CoinDetailViewModel]
        let voucherDetails: [VoucherDetailViewModel]
    }
#endif

struct CoinDetailViewModel: Identifiable {
    let id: String
    let exponent: String
    let state: String
    let age: String
}

struct VoucherDetailViewModel: Identifiable {
    let id: String
    let exponent: String
    let state: String
    let allocatedAt: String
    let readyAt: String
}

protocol AssetDetailsViewModelProtocol: Observation.Observable {
    var balanceCardModel: AssetDetailsBalanceCard.ViewModel? { get set }
    var showsBackupNotification: Bool { get set }
    #if TESTNET_FEATURE
        var coinageBreakdown: CoinageBalanceBreakdownViewModel? { get set }
    #endif
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

    #if TESTNET_FEATURE
        var isTestnetTopUpInProgress: Bool { get set }
        var onTestnetTopUp: (() -> Void)? { get set }
        var onMakeAllVouchersReady: (() -> Void)? { get set }
    #endif
}

@Observable
class AssetDetailsViewModel: AssetDetailsViewModelProtocol {
    var balanceCardModel: AssetDetailsBalanceCard.ViewModel?
    var showsBackupNotification: Bool = false
    #if TESTNET_FEATURE
        var coinageBreakdown: CoinageBalanceBreakdownViewModel?
    #endif
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

    #if TESTNET_FEATURE
        var isTestnetTopUpInProgress: Bool = false
        var onTestnetTopUp: (() -> Void)?
        var onMakeAllVouchersReady: (() -> Void)?
    #endif
}
