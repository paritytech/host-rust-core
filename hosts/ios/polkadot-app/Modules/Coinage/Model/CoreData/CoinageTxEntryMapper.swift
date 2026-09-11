import Foundation
import CoreData
import Coinage
import Operation_iOS
import SubstrateSdk

/// Maps ``CoinageTxEntry`` to `CDCoinageTxEntry`.
///
/// Inputs and outputs are immutable: they are written once when the entry is first inserted and
/// never rewritten, so a status update only touches the entry's own fields. Each row references
/// its asset through the `CDCoin` / `CDVoucher` relation — or `receivedPubKey` for a coin received
/// from a peer — which must already exist at registration.
final class CoinageTxEntryMapper: CoreDataMapperProtocol {
    typealias DataProviderModel = CoinageTxEntry
    typealias CoreDataEntity = CDCoinageTxEntry

    var entityIdentifierFieldName: String { #keyPath(CDCoinageTxEntry.identifier) }

    func transform(entity: CDCoinageTxEntry) throws -> CoinageTxEntry {
        guard let identifier = entity.identifier, let id = UUID(uuidString: identifier) else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDCoinageTxEntry.identifier))
        }
        guard let status = CoinageTxStatus(rawValue: Int(entity.status)) else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDCoinageTxEntry.status))
        }

        guard let checkpointHash = entity.checkpointHash, let checkpointNumber = entity.checkpointNumber else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDCoinageTxEntry.checkpointHash))
        }

        let checkpoint = try BlockRef(
            number: checkpointNumber.uint32Value,
            hash: Data(hexString: checkpointHash)
        )

        guard let txHashString = entity.txHash else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDCoinageTxEntry.txHash))
        }
        let txHash = try Data(hexString: txHashString)

        let successDetectedAt: BlockRef? =
            if let successHash = entity.successHash, let successNumber = entity.successNumber {
                try BlockRef(number: successNumber.uint32Value, hash: Data(hexString: successHash))
            } else {
                nil
            }

        guard let createdAt = entity.createdAt else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDCoinageTxEntry.createdAt))
        }

        return try CoinageTxEntry(
            id: id,
            sequence: entity.sequence,
            inputs: transformInputs(from: entity.inputs),
            outputs: transformOutputs(from: entity.outputs),
            groupId: entity.groupId,
            txHash: txHash,
            checkpoint: checkpoint,
            mortality: UInt32(bitPattern: entity.mortality),
            successDetectedAt: successDetectedAt,
            status: status,
            createdAt: createdAt
        )
    }

    func populate(
        entity: CDCoinageTxEntry,
        from model: CoinageTxEntry,
        using context: NSManagedObjectContext
    ) throws {
        let isNew = entity.identifier == nil

        entity.identifier = model.identifier
        entity.sequence = model.sequence
        entity.groupId = model.groupId
        entity.status = Int16(model.status.rawValue)
        entity.createdAt = model.createdAt
        entity.mortality = Int32(bitPattern: model.mortality)
        entity.checkpointHash = model.checkpoint.hash.toHex()
        entity.checkpointNumber = NSNumber(value: model.checkpoint.number)
        entity.txHash = model.txHash.toHex()
        entity.successHash = model.successDetectedAt?.hash.toHex()
        entity.successNumber = model.successDetectedAt.map { NSNumber(value: $0.number) }

        // Inputs and outputs never change once the entry exists — write them only on first insert.
        if isNew {
            try populateInputs(entity: entity, inputs: model.inputs, using: context)
            try populateOutputs(entity: entity, outputs: model.outputs, using: context)
        }

        touchRelatedAssets(of: entity, in: context)
    }
}

// MARK: - Transform

private extension CoinageTxEntryMapper {
    func transformInputs(from rows: NSSet?) throws -> [CoinageTxInput] {
        guard let rows = rows as? Set<CDCoinageTxInput> else { return [] }
        return try rows.compactMap { row in
            if let hex = row.receivedPubKey {
                return try .coin(.received(Data(hexString: hex)))
            }
            if let coin = row.coin {
                return try .coin(.own(DerivationIndex.fromCoreData(coin.derivationIndex), publicKey(coin.publicKey)))
            }
            if let voucher = row.voucher {
                return try .recyclerVoucher(
                    DerivationIndex.fromCoreData(voucher.derivationIndex),
                    publicKey(voucher.publicKey)
                )
            }
            return nil
        }
    }

    func transformOutputs(from rows: NSSet?) throws -> [OwnAsset] {
        guard let rows = rows as? Set<CDCoinageTxOutput> else { return [] }
        return try rows.compactMap { row in
            if let coin = row.coin {
                return try .coin(DerivationIndex.fromCoreData(coin.derivationIndex), publicKey(coin.publicKey))
            }
            if let voucher = row.voucher {
                return try .recyclerVoucher(
                    DerivationIndex.fromCoreData(voucher.derivationIndex),
                    publicKey(voucher.publicKey)
                )
            }
            return nil
        }
    }

    /// The stored on-chain public key of a linked coin/voucher row. Persisted at mint (coinage.md
    /// #1), so the entry never derives it on the fly.
    func publicKey(_ hex: String?) throws -> PublicKey {
        guard let hex else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDCoin.publicKey))
        }
        return try Data(hexString: hex)
    }
}

// MARK: - Populate

private extension CoinageTxEntryMapper {
    func populateInputs(
        entity: CDCoinageTxEntry,
        inputs: [CoinageTxInput],
        using context: NSManagedObjectContext
    ) throws {
        for input in inputs {
            guard let row = insert("CDCoinageTxInput", context) as CDCoinageTxInput? else {
                throw CoreDataMapperError.unsupported
            }

            row.entry = entity

            switch input {
            case let .coin(coinInput):
                switch coinInput {
                case .own:
                    if let coin = CoinageTxAssetLinker.coin(for: input, in: context) {
                        row.coin = coin
                    } else {
                        throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDCoinageTxInput.coin))
                    }
                case let .received(accountId):
                    row.receivedPubKey = accountId.toHex()
                }
            case .recyclerVoucher:
                if let voucher = CoinageTxAssetLinker.voucher(for: input, in: context) {
                    row.voucher = voucher
                } else {
                    throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDCoinageTxInput.voucher))
                }
            }
        }
    }

    func populateOutputs(
        entity: CDCoinageTxEntry,
        outputs: [OwnAsset],
        using context: NSManagedObjectContext
    ) throws {
        for output in outputs {
            guard let row = insert("CDCoinageTxOutput", context) as CDCoinageTxOutput? else {
                throw CoreDataMapperError.unsupported
            }

            row.entry = entity

            switch output {
            case .coin:
                if let coin = CoinageTxAssetLinker.coin(for: output, in: context) {
                    row.coin = coin
                } else {
                    throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDCoinageTxOutput.coin))
                }
            case .recyclerVoucher:
                if let voucher = CoinageTxAssetLinker.voucher(for: output, in: context) {
                    row.voucher = voucher
                } else {
                    throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDCoinageTxOutput.voucher))
                }
            }
        }
    }

    /// Signals the linked coins/vouchers as changed so their CoreData snapshot subscribers re-emit
    /// when this entry's status changes — the `willChange`/`didChange` TouchParent pattern.
    func touchRelatedAssets(of entity: CDCoinageTxEntry, in _: NSManagedObjectContext) {
        for row in (entity.inputs as? Set<CDCoinageTxInput>) ?? [] {
            if let coin = row.coin {
                let key = #keyPath(CDCoin.coinageTxInputs)
                coin.willChangeValue(forKey: key)
                coin.didChangeValue(forKey: key)
            }

            if let voucher = row.voucher {
                let key = #keyPath(CDVoucher.coinageTxInputs)
                voucher.willChangeValue(forKey: key)
                voucher.didChangeValue(forKey: key)
            }
        }

        for row in (entity.outputs as? Set<CDCoinageTxOutput>) ?? [] {
            if let coin = row.coin {
                let key = #keyPath(CDCoin.coinageTxOutput)
                coin.willChangeValue(forKey: key)
                coin.didChangeValue(forKey: key)
            }

            if let voucher = row.voucher {
                let key = #keyPath(CDVoucher.coinageTxOutput)
                voucher.willChangeValue(forKey: key)
                voucher.didChangeValue(forKey: key)
            }
        }
    }

    func insert<Entity: NSManagedObject>(_ entityName: String, _ context: NSManagedObjectContext) -> Entity? {
        NSEntityDescription.insertNewObject(forEntityName: entityName, into: context) as? Entity
    }
}
