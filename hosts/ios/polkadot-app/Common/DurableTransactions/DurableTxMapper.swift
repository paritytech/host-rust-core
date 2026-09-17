import CoreData
import DurableTransactions
import Foundation
import Operation_iOS
import SubstrateSdk

/// Maps the engine's ``DurableTxEntry`` to `CDDurableTx` — the domain-neutral fields only. A domain's
/// rows hang off the same entity through their own relations and are written by that domain's store.
final class DurableTxMapper: CoreDataMapperProtocol {
    typealias DataProviderModel = DurableTxEntry
    typealias CoreDataEntity = CDDurableTx

    var entityIdentifierFieldName: String { #keyPath(CDDurableTx.identifier) }

    func transform(entity: CDDurableTx) throws -> DurableTxEntry {
        guard let identifier = entity.identifier, let id = UUID(uuidString: identifier) else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDDurableTx.identifier))
        }
        guard let status = DurableTxStatus(rawValue: Int(entity.status)) else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDDurableTx.status))
        }
        guard let domainId = entity.domainId else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDDurableTx.domainId))
        }
        guard let checkpointHash = entity.checkpointHash, let checkpointNumber = entity.checkpointNumber else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDDurableTx.checkpointHash))
        }
        guard let txHashString = entity.txHash else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDDurableTx.txHash))
        }
        guard let createdAt = entity.createdAt else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDDurableTx.createdAt))
        }

        let successDetectedAt: BlockRef? =
            if let successHash = entity.successHash, let successNumber = entity.successNumber {
                try BlockRef(number: successNumber.uint32Value, hash: Data(hexString: successHash))
            } else {
                nil
            }

        return try DurableTxEntry(
            id: id,
            domainId: TxDomainId(domainId),
            sequence: entity.sequence,
            groupId: entity.groupId,
            txHash: Data(hexString: txHashString),
            checkpoint: BlockRef(number: checkpointNumber.uint32Value, hash: Data(hexString: checkpointHash)),
            mortality: UInt32(bitPattern: entity.mortality),
            successDetectedAt: successDetectedAt,
            status: status,
            createdAt: createdAt
        )
    }

    func populate(entity: CDDurableTx, from model: DurableTxEntry, using _: NSManagedObjectContext) throws {
        entity.identifier = model.identifier
        entity.domainId = model.domainId.rawValue
        entity.sequence = model.sequence
        entity.groupId = model.groupId
        entity.createdAt = model.createdAt
        entity.mortality = Int32(bitPattern: model.mortality)
        entity.checkpointHash = model.checkpoint.hash.toHex()
        entity.checkpointNumber = NSNumber(value: model.checkpoint.number)
        entity.txHash = model.txHash.toHex()
        Self.apply(status: model.status, successDetectedAt: model.successDetectedAt, to: entity)
    }

    /// The status write alone — what a verdict changes. Kept separate from a full populate so the
    /// compare-and-set touches nothing else.
    static func apply(status: DurableTxStatus, successDetectedAt: BlockRef?, to entity: CDDurableTx) {
        entity.status = Int16(status.rawValue)
        entity.successHash = successDetectedAt?.hash.toHex()
        entity.successNumber = successDetectedAt.map { NSNumber(value: $0.number) }
    }
}
