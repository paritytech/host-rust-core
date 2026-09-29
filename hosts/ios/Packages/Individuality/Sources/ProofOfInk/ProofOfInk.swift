import Foundation
import SubstrateSdk

public enum ProofOfInk {
    public struct Collection {
        public let familyIndex: ProofOfInkPallet.FamilyIndex
        public let family: ProofOfInkPallet.Family

        public init(
            familyIndex: ProofOfInkPallet.FamilyIndex,
            family: ProofOfInkPallet.Family
        ) {
            self.familyIndex = familyIndex
            self.family = family
        }
    }

    public enum Choice: Equatable {
        public struct Designed: Equatable {
            public let family: ProofOfInkPallet.FamilyIndex
            public let index: ProofOfInkPallet.DesignIndex
            public let familyId: ProofOfInkPallet.FamilyId

            public init(
                family: ProofOfInkPallet.FamilyIndex,
                index: ProofOfInkPallet.DesignIndex,
                familyId: ProofOfInkPallet.FamilyId
            ) {
                self.family = family
                self.index = index
                self.familyId = familyId
            }
        }

        public struct ProceduralAccount: Equatable {
            public let family: ProofOfInkPallet.FamilyIndex
            public let accountId: AccountId
            public let familyId: ProofOfInkPallet.FamilyId

            public init(
                family: ProofOfInkPallet.FamilyIndex,
                accountId: AccountId,
                familyId: ProofOfInkPallet.FamilyId
            ) {
                self.family = family
                self.accountId = accountId
                self.familyId = familyId
            }
        }

        public struct ProceduralPersonal: Equatable {
            public let family: ProofOfInkPallet.FamilyIndex
            public let personalId: ProofOfInkPallet.PersonalId
            public let familyId: ProofOfInkPallet.FamilyId

            public init(
                family: ProofOfInkPallet.FamilyIndex,
                personalId: ProofOfInkPallet.PersonalId,
                familyId: ProofOfInkPallet.FamilyId
            ) {
                self.family = family
                self.personalId = personalId
                self.familyId = familyId
            }
        }

        public struct Procedural: Equatable {
            public let family: ProofOfInkPallet.FamilyIndex
            public let variantIndex: ProofOfInkPallet.VariantIndex
            public let proceduralSeed: Data
            public let familyId: ProofOfInkPallet.FamilyId

            public init(
                family: ProofOfInkPallet.FamilyIndex,
                variantIndex: ProofOfInkPallet.VariantIndex,
                proceduralSeed: Data,
                familyId: ProofOfInkPallet.FamilyId
            ) {
                self.family = family
                self.variantIndex = variantIndex
                self.proceduralSeed = proceduralSeed
                self.familyId = familyId
            }
        }

        case designed(Designed)
        case proceduralAccount(ProceduralAccount)
        case proceduralPersonal(ProceduralPersonal)
        case procedural(Procedural)

        public var familyId: ProofOfInkPallet.FamilyId {
            switch self {
            case let .designed(designed):
                designed.familyId
            case let .proceduralAccount(proceduralAccount):
                proceduralAccount.familyId
            case let .proceduralPersonal(proceduralPersonal):
                proceduralPersonal.familyId
            case let .procedural(procedural):
                procedural.familyId
            }
        }
    }
}

public extension ProofOfInkPallet.InkSpec {
    init(choice: ProofOfInk.Choice) {
        switch choice {
        case let .designed(designed):
            self = .designedElective(.init(familyIndex: designed.family, design: designed.index))
        case let .proceduralAccount(proceduralAccount):
            self = .proceduralAccount(.init(
                familyIndex: proceduralAccount.family,
                accountId: proceduralAccount.accountId
            ))
        case let .proceduralPersonal(proceduralPersonal):
            self = .proceduralPersonal(.init(
                familyIndex: proceduralPersonal.family,
                personalId: proceduralPersonal.personalId
            ))
        case let .procedural(procedural):
            self = .procedural(.init(familyIndex: procedural.family, proceduralSeed: procedural.proceduralSeed))
        }
    }
}
