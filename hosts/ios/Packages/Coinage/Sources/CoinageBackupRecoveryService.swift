import Foundation
import Operation_iOS
import SDKLogger
import SubstrateSdk

// MARK: - ScanResult

public struct ScanResult<Item: CoinageDerivable> {
    public let items: [Item]
    public let horizon: Int
}

// MARK: - Protocol

public protocol CoinageBackupRecoveryServicing: Sendable {
    /// Scans the chain for coins belonging to the user up to the last known derivation index.
    /// When no index is stored, uses a gap-limit scan: stops after several consecutive batches
    /// that return no on-chain coins.
    /// Updates the coin indexstore with the highest found index after recovery.
    func recoverCoins() async throws -> ScanResult<Coin>

    /// Scans the chain for vouchers belonging to the user up to the last known derivation index.
    /// When no index is stored, uses a gap-limit scan: stops after several consecutive batches
    /// that return no on-chain vouchers.
    /// Updates the voucher indexstore with the highest found index after recovery.
    /// Recovered vouchers have `allocatedAt: .now` and `readyAt: .distantPast` since those
    /// dates are not recoverable from chain; `VoucherLocationService` reconciles state on startup.
    func recoverVouchers() async throws -> ScanResult<Voucher>

    /// Scans beyond the given startIndex using gap-limit strategy.
    /// Only updates the coin indexstore when coins are found.
    /// Returns discovered coins and the last scanned index (horizon).
    func extendScanCoins(from startIndex: Int) async throws -> ScanResult<Coin>

    /// Scans beyond the given startIndex using gap-limit strategy.
    /// Only updates the voucher indexstore when vouchers are found.
    /// Returns discovered vouchers and the last scanned index (horizon).
    func extendScanVouchers(from startIndex: Int) async throws -> ScanResult<Voucher>
}

// MARK: - Implementation

final class CoinageBackupRecoveryService: CoinageBackupRecoveryServicing, @unchecked Sendable {
    private enum Config {
        static let batchSize = 500
        static let gapLimit = 4
    }

    private let coinIndexstore: any CoinageIndexstoreProtocol
    private let voucherIndexstore: any CoinageIndexstoreProtocol
    private let coinKeypairFactory: any CoinKeyDeriving
    private let coinOnChainQuery: any CoinOnChainQuerying
    private let voucherOnChainQuery: any VoucherOnChainQuerying
    private let logger: (any SDKLoggerProtocol)?

    init(
        coinIndexstore: any CoinageIndexstoreProtocol,
        voucherIndexstore: any CoinageIndexstoreProtocol,
        coinKeypairFactory: any CoinKeyDeriving,
        coinOnChainQuery: any CoinOnChainQuerying,
        voucherOnChainQuery: any VoucherOnChainQuerying,
        logger: (any SDKLoggerProtocol)?
    ) {
        self.coinIndexstore = coinIndexstore
        self.voucherIndexstore = voucherIndexstore
        self.coinKeypairFactory = coinKeypairFactory
        self.coinOnChainQuery = coinOnChainQuery
        self.voucherOnChainQuery = voucherOnChainQuery
        self.logger = logger
    }

    func recoverCoins() async throws -> ScanResult<Coin> {
        let result: ScanResult<Coin>
        if let storedMax = try coinIndexstore.getCurrentIndex() {
            let coins = try await scanCoins(from: 0, through: Int(storedMax))
            result = ScanResult(items: coins, horizon: Int(storedMax))
        } else {
            result = try await scanCoinsWithGapLimit()
        }
        updateCoinIndex(from: result.items)
        return result
    }

    func recoverVouchers() async throws -> ScanResult<Voucher> {
        let result: ScanResult<Voucher>
        if let storedMax = try voucherIndexstore.getCurrentIndex() {
            let vouchers = try await scanVouchers(from: 0, through: Int(storedMax))
            result = ScanResult(items: vouchers, horizon: Int(storedMax))
        } else {
            result = try await scanVouchersWithGapLimit()
        }
        updateVoucherIndex(from: result.items)
        return result.excludingUnloaded()
    }

    func extendScanCoins(from startIndex: Int) async throws -> ScanResult<Coin> {
        let scanResult = try await scanCoinsWithGapLimit(from: startIndex)
        updateCoinIndex(from: scanResult.items)
        return scanResult
    }

    func extendScanVouchers(from startIndex: Int) async throws -> ScanResult<Voucher> {
        let scanResult = try await scanVouchersWithGapLimit(from: startIndex)
        updateVoucherIndex(from: scanResult.items)
        return scanResult.excludingUnloaded()
    }
}

// MARK: - Coins

private extension CoinageBackupRecoveryService {
    func updateCoinIndex(from coins: [Coin]) {
        guard let highest = coins.map(\.derivationIndex).max() else {
            return
        }
        try? coinIndexstore.setCurrentIndex(highest)
    }

    func scanCoins(from start: Int, through end: Int) async throws -> [Coin] {
        var result: [Coin] = []

        for batchStart in stride(from: start, through: end, by: Config.batchSize) {
            let batchEnd = min(batchStart + Config.batchSize - 1, end)
            let indexedKeys = await deriveCoinKeys(in: batchStart ... batchEnd)
            let coins = try await queryCoinBatch(indexedKeys: indexedKeys)
            result.append(contentsOf: coins)
        }

        return result
    }

    /// Scans coins starting from `startIndex`, stopping after `gapLimit` consecutive batches
    /// of `batchSize` indices that yield no on-chain results (gap-limit strategy).
    func scanCoinsWithGapLimit(from startIndex: Int = 0) async throws -> ScanResult<Coin> {
        var result: [Coin] = []
        var batchStart = startIndex
        var emptyBatches = 0

        while emptyBatches < Config.gapLimit {
            let batchEnd = batchStart + Config.batchSize - 1
            let indexedKeys = await deriveCoinKeys(in: batchStart ... batchEnd)
            let coins = try await queryCoinBatch(indexedKeys: indexedKeys)

            if coins.isEmpty {
                emptyBatches += 1
            } else {
                emptyBatches = 0
                result.append(contentsOf: coins)
            }

            batchStart += Config.batchSize
        }

        return ScanResult(items: result, horizon: batchStart - 1)
    }

    func deriveCoinKeys(in range: ClosedRange<Int>) async -> [(index: DerivationIndex, publicKey: Data)] {
        await withCheckedContinuation { continuation in
            let keys = range.compactMap { index in
                do {
                    let key = try coinKeypairFactory.derivePublicKey(index: DerivationIndex(index))
                    return (DerivationIndex(index), key)
                } catch {
                    logger?.error("Failed to derive coin key at index \(index): \(error)")
                    return nil
                }
            }
            continuation.resume(returning: keys.sorted { $0.0 < $1.0 })
        }
    }

    func queryCoinBatch(indexedKeys: [(index: DerivationIndex, publicKey: Data)]) async throws -> [Coin] {
        guard !indexedKeys.isEmpty else { return [] }
        let results = try await coinOnChainQuery.fetchCoins(for: indexedKeys.map(\.publicKey))
        return results.enumerated().compactMap { i, onChainCoin -> Coin? in
            guard let onChainCoin else { return nil }
            return Coin(
                exponent: Int16(onChainCoin.value),
                derivationIndex: indexedKeys[i].index,
                age: onChainCoin.age,
                publicKey: indexedKeys[i].publicKey
            )
        }
    }
}

// MARK: - Vouchers

private extension CoinageBackupRecoveryService {
    func updateVoucherIndex(from vouchers: [Voucher]) {
        guard let highest = vouchers.map(\.derivationIndex).max() else {
            return
        }
        try? voucherIndexstore.setCurrentIndex(highest)
    }

    func scanVouchers(from start: Int, through end: Int) async throws -> [Voucher] {
        var result: [Voucher] = []

        for batchStart in stride(from: start, through: end, by: Config.batchSize) {
            let batchEnd = min(batchStart + Config.batchSize - 1, end)
            let indices = (batchStart ... batchEnd).map { DerivationIndex($0) }
            let vouchers = try await queryVoucherBatch(indices: indices)
            result.append(contentsOf: vouchers)
        }

        return result
    }

    /// Scans vouchers starting from `startIndex`, stopping after `gapLimit` consecutive batches
    /// of `batchSize` indices that yield no on-chain results (gap-limit strategy).
    func scanVouchersWithGapLimit(from startIndex: Int = 0) async throws -> ScanResult<Voucher> {
        var result: [Voucher] = []
        var batchStart = startIndex
        var emptyBatches = 0

        while emptyBatches < Config.gapLimit {
            let batchEnd = batchStart + Config.batchSize - 1
            let indices = (batchStart ... batchEnd).map { DerivationIndex($0) }
            let vouchers = try await queryVoucherBatch(indices: indices)

            if vouchers.isEmpty {
                emptyBatches += 1
            } else {
                emptyBatches = 0
                result.append(contentsOf: vouchers)
            }

            batchStart += Config.batchSize
        }

        return ScanResult(items: result, horizon: batchStart - 1)
    }

    func queryVoucherBatch(indices: [DerivationIndex]) async throws -> [Voucher] {
        guard !indices.isEmpty else { return [] }
        let results = try await voucherOnChainQuery.fetchVouchers(for: indices)
        return zip(indices, results).compactMap { index, info -> Voucher? in
            // Only vouchers placed in a ring: the query now also reports Onboarding/Suspended members,
            // which backup recovery has never scanned, so it keeps to ring-placed ones as before.
            guard let info, info.ringPosition.ringIndex != nil else { return nil }
            return Voucher(
                exponent: info.exponent,
                derivationIndex: index,
                allocatedAt: .now,
                readyAt: .distantPast,
                remoteState: info.onChainState,
                publicKey: info.publicKey
            )
        }
    }
}

private extension ScanResult where Item == Voucher {
    func excludingUnloaded() -> ScanResult<Voucher> {
        ScanResult(items: items.filter { $0.remoteState != .unlocated }, horizon: horizon)
    }
}
