import Foundation
import SubstrateSdk
import Coinage
import ChainRegistry
import Products

protocol WalletFlowContextProtocol {
    var depositService: DepositServiceProtocol { get }
    var fiatOnrampService: FiatOnrampServicing { get }
    var fiatOnrampTrackingService: FiatOnrampTrackingServiceProtocol { get }
    var coinageService: CoinageServicing { get }
    var coinageBackupSyncService: CoinageBackupSyncServicing { get }
    var personDataStore: DetermineStatePersonDataStore { get }
    var balanceSyncStateStorage: BalanceSyncStateStoring { get }
    var networkStatusService: NetworkStatusProviding { get }
    var flowState: SPAFlowState { get }
}

final class WalletFlowContext: WalletFlowContextProtocol {
    let depositService: DepositServiceProtocol
    let fiatOnrampService: FiatOnrampServicing
    let fiatOnrampTrackingService: FiatOnrampTrackingServiceProtocol
    let coinageService: CoinageServicing
    let coinageBackupSyncService: CoinageBackupSyncServicing
    let personDataStore: DetermineStatePersonDataStore
    let balanceSyncStateStorage: BalanceSyncStateStoring
    let networkStatusService: NetworkStatusProviding
    let flowState: SPAFlowState

    init(
        depositService: DepositServiceProtocol,
        fiatOnrampService: FiatOnrampServicing,
        fiatOnrampTrackingService: FiatOnrampTrackingServiceProtocol,
        coinageService: CoinageServicing,
        coinageBackupSyncService: CoinageBackupSyncServicing,
        personDataStore: DetermineStatePersonDataStore,
        networkStatusService: NetworkStatusProviding,
        balanceSyncStateStorage: BalanceSyncStateStoring = BalanceSyncStateStorage(),
        flowState: SPAFlowState
    ) {
        self.depositService = depositService
        self.fiatOnrampService = fiatOnrampService
        self.fiatOnrampTrackingService = fiatOnrampTrackingService
        self.coinageService = coinageService
        self.coinageBackupSyncService = coinageBackupSyncService
        self.personDataStore = personDataStore
        self.networkStatusService = networkStatusService
        self.balanceSyncStateStorage = balanceSyncStateStorage
        self.flowState = flowState
    }
}
