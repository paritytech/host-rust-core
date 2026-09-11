import AsyncExtensions
import Coinage
import CommonService
import Foundation
import Keystore_iOS
import Operation_iOS

// MARK: - State

enum CoinageRecoveryState {
    case idle
    case inProgress
    case completed
    case failed(Error)
}

// MARK: - Protocol

protocol CoinageBackupSyncServicing: AsyncApplicationServicing {
    /// Current recovery state stream. Replays last state to new subscribers.
    /// Terminal states (.completed, .failed) are followed by .idle after emission.
    var stateStream: AnyAsyncSequence<CoinageRecoveryState> { get }

    /// Triggers a new recovery scan, cancelling any in-flight scan.
    /// Always runs regardless of the first-launch guard in setup().
    func triggerRecovery()
}

// MARK: - Implementation

final class CoinageBackupSyncService: CoinageBackupSyncServicing, @unchecked Sendable {
    private let coinageService: any CoinageServicing
    private let coinRepository: AnyDataProviderRepository<Coin>
    private let voucherRepository: AnyDataProviderRepository<Voucher>
    private let settingsManager: SettingsManagerProtocol
    private let balanceSyncStateStorage: BalanceSyncStateStoring
    private let logger: LoggerProtocol

    private let stateSubject = AsyncCurrentValueSubject<CoinageRecoveryState>(.idle)
    private var recoveryTask: Task<Void, Never>?

    var stateStream: AnyAsyncSequence<CoinageRecoveryState> {
        stateSubject.eraseToAnyAsyncSequence()
    }

    init(
        coinageService: any CoinageServicing,
        coinRepository: AnyDataProviderRepository<Coin>,
        voucherRepository: AnyDataProviderRepository<Voucher>,
        settingsManager: SettingsManagerProtocol = SettingsManager.shared,
        balanceSyncStateStorage: BalanceSyncStateStoring = BalanceSyncStateStorage(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.coinageService = coinageService
        self.coinRepository = coinRepository
        self.voucherRepository = voucherRepository
        self.settingsManager = settingsManager
        self.balanceSyncStateStorage = balanceSyncStateStorage
        self.logger = logger
    }

    /// Auto-triggers recovery after wallet restore from iCloud or mnemonic.
    func setup() async {
        guard settingsManager.value(for: .coinageSyncNeeded) else { return }
        stateSubject.send(.inProgress)
        await performRecovery(extended: false)
    }

    func throttle() async {
        recoveryTask?.cancel()
        recoveryTask = nil
        stateSubject.send(.idle)
    }

    func triggerRecovery() {
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            await performRecovery(extended: true)
        }
        stateSubject.send(.inProgress)
    }
}

// MARK: - Recovery logic

private extension CoinageBackupSyncService {
    func fetchScanResults(extendOnly: Bool) async throws -> RecoveryScanResult {
        if extendOnly {
            let coinHorizon = settingsManager.integer(for: .coinScanHorizon) ?? 0
            let voucherHorizon = settingsManager.integer(for: .voucherScanHorizon) ?? 0
            let result = try await coinageService.extendScanCoinsAndVouchers(
                coinHorizon: coinHorizon,
                voucherHorizon: voucherHorizon
            )
            return RecoveryScanResult(
                coins: result.coins.items,
                vouchers: result.vouchers.items,
                coinHorizon: result.coins.horizon,
                voucherHorizon: result.vouchers.horizon
            )
        } else {
            let result = try await coinageService.recoverCoinsAndVouchers()
            return RecoveryScanResult(
                coins: result.coins.items,
                vouchers: result.vouchers.items,
                coinHorizon: result.coins.horizon,
                voucherHorizon: result.vouchers.horizon
            )
        }
    }

    func filterNew(from scan: RecoveryScanResult) async throws -> RecoveryScanResult {
        let fetchOptions = RepositoryFetchOptions()
        let localCoins = try await coinRepository.fetchAllOperation(with: fetchOptions).asyncExecute()
        let localVouchers = try await voucherRepository
            .fetchAllOperation(with: fetchOptions)
            .asyncExecute()

        let localCoinIds = Set(localCoins.map(\.identifier))
        let localVoucherIds = Set(localVouchers.map(\.identifier))

        return RecoveryScanResult(
            coins: scan.coins.filter { !localCoinIds.contains($0.identifier) },
            vouchers: scan.vouchers.filter { !localVoucherIds.contains($0.identifier) },
            coinHorizon: scan.coinHorizon,
            voucherHorizon: scan.voucherHorizon
        )
    }

    func save(_ scanResult: RecoveryScanResult) async throws {
        if !scanResult.coins.isEmpty {
            try await coinRepository.saveOperation({ scanResult.coins }, { [] }).asyncExecute()
        }
        if !scanResult.vouchers.isEmpty {
            try await voucherRepository.saveOperation({ scanResult.vouchers }, { [] }).asyncExecute()
        }

        settingsManager.set(value: scanResult.coinHorizon, for: .coinScanHorizon)
        settingsManager.set(value: scanResult.voucherHorizon, for: .voucherScanHorizon)
    }

    func performRecovery(extended: Bool) async {
        guard !Task.isCancelled else { return }

        do {
            let scan = try await fetchScanResults(extendOnly: extended)
            try Task.checkCancellation()

            let newItems = try await filterNew(from: scan)
            try Task.checkCancellation()

            try await save(newItems)
            settingsManager.set(value: false, for: .coinageSyncNeeded)
            balanceSyncStateStorage.isRestorePending = true
            stateSubject.send(.completed)
            logger
                .debug(
                    "Coinage backup sync completed: \(newItems.coins.count) coins, \(newItems.vouchers.count) vouchers"
                )
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("Coinage backup sync failed: \(error)")
            stateSubject.send(.failed(error))
        }
    }
}

private struct RecoveryScanResult {
    let coins: [Coin]
    let vouchers: [Voucher]
    let coinHorizon: Int
    let voucherHorizon: Int
}
