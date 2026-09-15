import Foundation
import Foundation_iOS
import SubstrateSdk
import SubstrateStorageQuery

public struct MembershipStatusInput {
    let memberKey: MembersPallet.RingMember
    let collection: MembersPallet.CollectionIdentifier

    public init(memberKey: MembersPallet.RingMember, collection: MembersPallet.CollectionIdentifier) {
        self.memberKey = memberKey
        self.collection = collection
    }
}

public protocol MembershipStatusChecking {
    func checkStatuses(
        of inputs: [MembershipStatusInput],
        blockHash: BlockHashData?
    ) async throws -> [MembersPallet.RingMember: MembersPallet.RingIndex]
}

// check whether a given member key is included into a ring collection
// we assume the member key can't be part of several collections
public class MembershipStatusChecker {
    struct Inclusion {
        let collection: MembersPallet.CollectionIdentifier
        let ringIndex: MembersPallet.RingIndex
        let ringPosition: UInt32
    }

    struct RingStatusKey: Hashable {
        let collection: MembersPallet.CollectionIdentifier
        let ringIndex: MembersPallet.RingIndex
    }

    typealias InclusionByMember = [MembersPallet.RingMember: Inclusion]

    private let connection: JSONRPCEngine
    private let runtimeCodingService: RuntimeCodingServiceProtocol

    private let requestFactory = StorageRequestFactory.asyncInit()

    public init(
        connection: JSONRPCEngine,
        runtimeCodingService: RuntimeCodingServiceProtocol
    ) {
        self.connection = connection
        self.runtimeCodingService = runtimeCodingService
    }
}

private extension MembershipStatusChecker {
    func fetchInclusions(
        of inputs: [MembershipStatusInput],
        blockHash: BlockHashData?,
        codingFactory: RuntimeCoderFactoryProtocol
    ) async throws -> InclusionByMember {
        let ringPositions: [MembersPallet.RingPosition?] = try await requestFactory.queryItems(
            engine: connection,
            keyParams1: { inputs.map { BytesCodable(wrappedValue: $0.collection) } },
            keyParams2: { inputs.map { BytesCodable(wrappedValue: $0.memberKey) } },
            factory: { codingFactory },
            storagePath: MembersPallet.Storage.members(),
            at: blockHash
        )
        .asyncExecute()
        .map(\.value)

        return zip(inputs, ringPositions).reduce(into: [:]) { accum, pair in
            guard let ringIndex = pair.1?.ringIndex, let position = pair.1?.includedRingPosition else {
                return
            }

            accum[pair.0.memberKey] = Inclusion(
                collection: pair.0.collection,
                ringIndex: ringIndex,
                ringPosition: position
            )
        }
    }

    func fetchRingKeysStatuses(
        for keys: [RingStatusKey],
        blockHash: BlockHashData?,
        codingFactory: RuntimeCoderFactoryProtocol
    ) async throws -> [RingStatusKey: MembersPallet.RingKeysStatus] {
        let statuses: [MembersPallet.RingKeysStatus?] = try await requestFactory.queryItems(
            engine: connection,
            keyParams1: { keys.map(\.collection) },
            keyParams2: { keys.map { StringCodable(wrappedValue: $0.ringIndex) } },
            factory: { codingFactory },
            storagePath: MembersPallet.Storage.ringKeysStatus(),
            at: blockHash
        ).asyncExecute()
            .map(\.value)

        return zip(keys, statuses).reduce(into: [:]) {
            $0[$1.0] = $1.1
        }
    }
}

extension MembershipStatusChecker: MembershipStatusChecking {
    public func checkStatuses(
        of inputs: [MembershipStatusInput],
        blockHash: BlockHashData?
    ) async throws -> [MembersPallet.RingMember: MembersPallet.RingIndex] {
        let codingFactory = try await runtimeCodingService.fetchCoderFactoryOperation().asyncExecute()

        let inclusions = try await fetchInclusions(
            of: inputs,
            blockHash: blockHash,
            codingFactory: codingFactory
        )

        let ringStatusKeys = inclusions.values.map { value in
            RingStatusKey(collection: value.collection, ringIndex: value.ringIndex)
        }
        .distinct()

        let statuses = try await fetchRingKeysStatuses(
            for: ringStatusKeys,
            blockHash: blockHash,
            codingFactory: codingFactory
        )

        return inputs.reduce(into: [:]) { accum, input in
            guard let inclusion = inclusions[input.memberKey] else {
                return
            }

            let ringStatusKey = RingStatusKey(collection: inclusion.collection, ringIndex: inclusion.ringIndex)

            guard let status = statuses[ringStatusKey], status.includesKeyByRawPosition(inclusion.ringPosition) else {
                return
            }

            accum[input.memberKey] = inclusion.ringIndex
        }
    }
}
