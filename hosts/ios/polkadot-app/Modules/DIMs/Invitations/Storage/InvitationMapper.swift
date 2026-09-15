import Foundation
import CoreData
import Operation_iOS

final class InvitationMapper: CoreDataMapperProtocol {
    typealias DataProviderModel = Invitation

    typealias CoreDataEntity = CDInvitation

    var entityIdentifierFieldName: String { #keyPath(CDInvitation.type) }

    func transform(entity: CDInvitation) throws -> Invitation {
        guard let type = Invitation.InvitationType(rawValue: entity.type ?? "") else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CoreDataEntity.type))
        }
        guard let owner = entity.owner else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CoreDataEntity.owner))
        }
        guard let issuer = entity.issuer else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CoreDataEntity.issuer))
        }
        guard let publicKey = entity.publicKey else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CoreDataEntity.publicKey))
        }
        guard let signature = entity.signature else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CoreDataEntity.signature))
        }

        return Invitation(
            type: type,
            owner: owner,
            issuer: issuer,
            publicKey: publicKey,
            signature: signature
        )
    }

    func populate(
        entity: CDInvitation,
        from model: Invitation,
        using _: NSManagedObjectContext
    ) throws {
        entity.type = model.type.rawValue
        entity.owner = model.owner
        entity.issuer = model.issuer
        entity.publicKey = model.publicKey
        entity.signature = model.signature
    }
}

extension Invitation: Identifiable {
    var identifier: String { type.rawValue }
}
