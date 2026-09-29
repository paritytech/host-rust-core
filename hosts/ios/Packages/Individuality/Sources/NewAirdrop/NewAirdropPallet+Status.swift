import Foundation
import SubstrateSdk

public extension NewAirdropPallet {
    enum Status: Decodable, Equatable {
        case scheduled
        case registering(Registering)
        case drawWinners(DrawWinners)
        case claiming(Claiming)
        case clearingRegistrations(ClearingRegistrations)
        case clearingWinners(ClearingWinners)
        case finalizing(Finalizing)

        public struct Registering: Decodable, Equatable {
            @StringCodable public var totalParticipants: UInt32
        }

        public struct DrawWinners: Decodable, Equatable {
            @StringCodable public var totalParticipants: UInt32
            @StringCodable public var effectiveWinners: UInt32
            @StringCodable public var winnersAdded: UInt32
            @BytesCodable public var fromWinnerKey: Slot
        }

        public struct Claiming: Decodable, Equatable {
            @StringCodable public var totalParticipants: UInt32
            @StringCodable public var effectiveWinners: UInt32
            @StringCodable public var claimed: UInt32
        }

        public struct ClearingRegistrations: Decodable, Equatable {
            @StringCodable public var totalParticipants: UInt32
            @StringCodable public var effectiveWinners: UInt32
            @StringCodable public var claimed: UInt32
            @StringCodable public var cleanedRegistrations: UInt32
        }

        public struct ClearingWinners: Decodable, Equatable {
            @StringCodable public var totalParticipants: UInt32
            @StringCodable public var effectiveWinners: UInt32
            @StringCodable public var claimed: UInt32
            @StringCodable public var cleanedWinners: UInt32
        }

        public struct Finalizing: Decodable, Equatable {
            @StringCodable public var effectiveWinners: UInt32
            @StringCodable public var claimed: UInt32
        }

        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let variant = try container.decode(String.self)

            switch variant {
            case "Scheduled":
                self = .scheduled
            case "Registering":
                self = try .registering(container.decode(Registering.self))
            case "DrawWinners":
                self = try .drawWinners(container.decode(DrawWinners.self))
            case "Claiming":
                self = try .claiming(container.decode(Claiming.self))
            case "ClearingRegistrations":
                self = try .clearingRegistrations(container.decode(ClearingRegistrations.self))
            case "ClearingWinners":
                self = try .clearingWinners(container.decode(ClearingWinners.self))
            case "Finalizing":
                self = try .finalizing(container.decode(Finalizing.self))
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported Status variant: \(variant)"
                )
            }
        }
    }
}

public extension NewAirdropPallet.Status {
    var totalParticipants: UInt32? {
        switch self {
        case .scheduled: nil
        case let .registering(s): s.totalParticipants
        case let .drawWinners(s): s.totalParticipants
        case let .claiming(s): s.totalParticipants
        case let .clearingRegistrations(s): s.totalParticipants
        case let .clearingWinners(s): s.totalParticipants
        case .finalizing: nil
        }
    }

    var effectiveWinners: UInt32? {
        switch self {
        case .scheduled,
             .registering: nil
        case let .drawWinners(s): s.effectiveWinners
        case let .claiming(s): s.effectiveWinners
        case let .clearingRegistrations(s): s.effectiveWinners
        case let .clearingWinners(s): s.effectiveWinners
        case let .finalizing(s): s.effectiveWinners
        }
    }
}
