import Foundation
import CoreData
import Operation_iOS
import SubstrateSdk
import Individuality

struct LocalPrivacyVoucher: Codable, Identifiable, Equatable {
    let key: MemberKeyData
    let alias: Data
    let type: PrivacyVoucherType
    let index: Int
    let isClaimed: Bool

    var identifier: String { "\(type.rawValue)_\(index)" }

    func markedAsClaimed() -> LocalPrivacyVoucher {
        .init(
            key: key,
            alias: alias,
            type: type,
            index: index,
            isClaimed: true
        )
    }
}

func == (lhs: LocalPrivacyVoucher, rhs: LocalPrivacyVoucher) -> Bool {
    lhs.identifier == rhs.identifier
}

struct RemotePrivacyVoucher: Codable, Equatable {
    let localData: LocalPrivacyVoucher
    let status: PrivacyVoucherStatus
    let balanceOf: Balance
    let ringIndex: MembersPallet.RingIndex

    func markedAsClaimed() -> RemotePrivacyVoucher {
        .init(
            localData: localData.markedAsClaimed(),
            status: .used,
            balanceOf: balanceOf,
            ringIndex: ringIndex
        )
    }
}

func == (lhs: RemotePrivacyVoucher, rhs: RemotePrivacyVoucher) -> Bool {
    lhs.localData == rhs.localData
}

enum PrivacyVoucherType: String, Codable, CaseIterable {
    case reimbursement
    case referral
    case mobRule
    case scoreReward
}

enum PrivacyVoucherStatus: String, Codable {
    case claimable
    case building
    case used
}

final class LocalPrivacyVoucherMapper: CoreDataMapperProtocol {
    var entityIdentifierFieldName: String {
        #keyPath(CoreDataEntity.identifier)
    }

    typealias DataProviderModel = LocalPrivacyVoucher
    typealias CoreDataEntity = CDLocalPrivacyVoucher

    func populate(
        entity: CoreDataEntity,
        from model: DataProviderModel,
        using _: NSManagedObjectContext
    ) throws {
        entity.memberKey = model.key.memberKey
        entity.entropy = model.key.entropy
        entity.alias = model.alias
        entity.type = model.type.rawValue
        entity.index = Int64(model.index)
        entity.identifier = model.identifier
        entity.isClaimed = model.isClaimed
    }

    func transform(entity: CoreDataEntity) throws -> DataProviderModel {
        guard let memberKey = entity.memberKey else {
            throw CoreDataMapperError.missingRequiredData(
                keyPath: #keyPath(CoreDataEntity.memberKey)
            )
        }

        guard let entropy = entity.entropy else {
            throw CoreDataMapperError.missingRequiredData(
                keyPath: #keyPath(CoreDataEntity.entropy)
            )
        }

        guard let alias = entity.alias else {
            throw CoreDataMapperError.missingRequiredData(
                keyPath: #keyPath(CoreDataEntity.alias)
            )
        }

        guard
            let rawType = entity.type,
            let type = PrivacyVoucherType(rawValue: rawType)
        else {
            throw CoreDataMapperError.missingRequiredData(
                keyPath: #keyPath(CoreDataEntity.type)
            )
        }

        return LocalPrivacyVoucher(
            key: .init(entropy: entropy, memberKey: memberKey),
            alias: alias,
            type: type,
            index: Int(entity.index),
            isClaimed: entity.isClaimed
        )
    }
}
