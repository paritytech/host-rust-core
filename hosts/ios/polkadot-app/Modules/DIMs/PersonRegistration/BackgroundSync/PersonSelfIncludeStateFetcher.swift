import Foundation
import SubstrateSdk
import SubstrateStorageQuery
import StructuredConcurrency
import KeyDerivation
import Individuality
import ChainRegistry

protocol PersonSelfIncludeStateFetching: AnyObject {
    func fetchEligibility() async throws -> PersonRegistration.SelfIncludeEligibility
}

final class PersonSelfIncludeStateFetcher: PersonSelfIncludeStateFetching {
    private let vrfManager: BandersnatchKeyManaging
    private let chain: ChainModel
    private let runtimeProvider: RuntimeProviderProtocol
    private let connectionFactory: ConnectionFactoryProtocol
    private let logger: LoggerProtocol

    private lazy var requestFactory = StorageRequestFactory.asyncInit()

    init(
        vrfManager: BandersnatchKeyManaging,
        chain: ChainModel,
        runtimeProvider: RuntimeProviderProtocol,
        connectionFactory: ConnectionFactoryProtocol,
        logger: LoggerProtocol
    ) {
        self.vrfManager = vrfManager
        self.chain = chain
        self.runtimeProvider = runtimeProvider
        self.connectionFactory = connectionFactory
        self.logger = logger
    }

    func fetchEligibility() async throws -> PersonRegistration.SelfIncludeEligibility {
        let memberKey = try vrfManager.getMemberKey()
        let connection = try connectionFactory.createConnection(for: chain, delegate: nil)
        defer { connection.disconnect(true) }

        let codingFactory = try await runtimeProvider.fetchCoderFactoryOperation().asyncExecute()

        async let position = fetchRingPosition(
            connection: connection,
            memberKey: memberKey,
            codingFactory: codingFactory
        )
        async let collection = fetchCollectionInfo(
            connection: connection,
            codingFactory: codingFactory
        )
        async let timestampMs = fetchTimestampMs(
            connection: connection,
            codingFactory: codingFactory
        )
        async let ringsState = fetchRingsState(
            connection: connection,
            codingFactory: codingFactory
        )

        return try await PersonRegistration.SelfIncludeEligibility.evaluate(
            position: position,
            collectionInfo: collection,
            ringsState: ringsState,
            bestBlockTimestampMs: timestampMs
        )
    }
}

private extension PersonSelfIncludeStateFetcher {
    func fetchRingPosition(
        connection: JSONRPCEngine,
        memberKey: BandersnatchPubKey,
        codingFactory: RuntimeCoderFactoryProtocol
    ) async throws -> MembersPallet.RingPosition? {
        try await requestFactory.queryItems(
            engine: connection,
            keyParams1: { [BytesCodable(wrappedValue: PeoplePallet.membersIdentifier)] },
            keyParams2: { [BytesCodable(wrappedValue: memberKey)] },
            factory: { codingFactory },
            storagePath: MembersPallet.Storage.members()
        )
        .asyncExecute()
        .first?.value
    }

    func fetchCollectionInfo(
        connection: JSONRPCEngine,
        codingFactory: RuntimeCoderFactoryProtocol
    ) async throws -> MembersPallet.CollectionInfo? {
        try await requestFactory.queryItems(
            engine: connection,
            keyParams: { [BytesCodable(wrappedValue: PeoplePallet.membersIdentifier)] },
            factory: { codingFactory },
            storagePath: MembersPallet.Storage.collections()
        )
        .asyncExecute()
        .first?.value
    }

    func fetchTimestampMs(
        connection: JSONRPCEngine,
        codingFactory: RuntimeCoderFactoryProtocol
    ) async throws -> BlockTime? {
        let response: StorageResponse<StringScaleMapper<BlockTime>> = try await requestFactory.queryItem(
            engine: connection,
            factory: { codingFactory },
            storagePath: TimestampPallet.timestampNowPath
        )
        .asyncExecute()
        return response.value?.value
    }

    func fetchRingsState(
        connection: JSONRPCEngine,
        codingFactory: RuntimeCoderFactoryProtocol
    ) async throws -> MembersPallet.RingMembersState? {
        try await requestFactory.queryItems(
            engine: connection,
            keyParams: { [BytesCodable(wrappedValue: PeoplePallet.membersIdentifier)] },
            factory: { codingFactory },
            storagePath: MembersPallet.Storage.ringsState()
        )
        .asyncExecute()
        .first?.value
    }
}
