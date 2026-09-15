import BigInt
import Coinage
import CoreData
import Operation_iOS

/// Maps between ``ExternalPayment`` domain models and `CDExternalPayment` CoreData entities.
final class ExternalPaymentMapper: CoreDataMapperProtocol {
    typealias DataProviderModel = ExternalPayment
    typealias CoreDataEntity = CDExternalPayment

    var entityIdentifierFieldName: String { #keyPath(CDExternalPayment.identifier) }

    func transform(entity: CDExternalPayment) throws -> ExternalPayment {
        guard let identifier = entity.identifier,
              let origin = entity.origin,
              let amountString = entity.amountInPlanks,
              let destination = entity.destination,
              let readyAt = entity.readyAt,
              let createdAt = entity.createdAt,
              let updatedAt = entity.updatedAt
        else {
            throw ExternalPaymentMapperError.missingRequiredField
        }

        let amount = BigUInt(amountString) ?? 0
        let stage = ExternalPayment.Stage(rawValue: Int(entity.stage)) ?? .plan

        return ExternalPayment(
            id: identifier,
            origin: origin,
            amountInPlanks: amount,
            destination: destination,
            stage: stage,
            failureReason: entity.failureReason,
            readyAt: readyAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func populate(
        entity: CDExternalPayment,
        from model: ExternalPayment,
        using _: NSManagedObjectContext
    ) throws {
        entity.identifier = model.id
        entity.origin = model.origin
        entity.amountInPlanks = String(model.amountInPlanks)
        entity.destination = model.destination
        entity.stage = Int16(model.stage.rawValue)
        entity.failureReason = model.failureReason
        entity.readyAt = model.readyAt
        entity.createdAt = model.createdAt
        entity.updatedAt = model.updatedAt
    }
}

/// Partial mapper that updates only mutable fields on an existing `CDExternalPayment`.
///
/// Use for stage transitions — avoids re-writing immutable fields like origin, destination, amount.
final class ExternalPaymentStageMapper: CoreDataMapperProtocol {
    enum MappingError: Error {
        case noExistingEntity
    }

    typealias DataProviderModel = ExternalPayment
    typealias CoreDataEntity = CDExternalPayment

    var entityIdentifierFieldName: String { #keyPath(CDExternalPayment.identifier) }

    func transform(entity: CDExternalPayment) throws -> ExternalPayment {
        try ExternalPaymentMapper().transform(entity: entity)
    }

    func populate(
        entity: CDExternalPayment,
        from model: ExternalPayment,
        using _: NSManagedObjectContext
    ) throws {
        guard entity.identifier != nil else {
            throw MappingError.noExistingEntity
        }
        entity.stage = Int16(model.stage.rawValue)
        entity.failureReason = model.failureReason
        entity.readyAt = model.readyAt
        entity.updatedAt = model.updatedAt
    }
}

private enum ExternalPaymentMapperError: Error {
    case missingRequiredField
}
