import Foundation
import SubstrateSdk
import SubstrateStorageSubscription
import StructuredConcurrency
import KeyDerivation
import Individuality
import ChainRegistry

protocol AirdropServicing {
    func makeProof(for gameInfo: GameInfo) async throws -> GamePallet.AirdropVrfs?

    func subscribeEventStatus(
        forGameIndex gameIndex: GamePallet.GameIndex
    ) -> AsyncStream<NewAirdropPallet.Status?>
}

final class AirdropService {
    private let chainRegistry: ChainRegistryProtocol
    private let candidateWallet: WalletManaging
    private let vrfManager: BandersnatchKeyManaging
    private let personDataStore: DetermineStatePersonDataStore
    private let logger: LoggerProtocol

    init(
        chainRegistry: ChainRegistryProtocol,
        candidateWallet: WalletManaging,
        vrfManager: BandersnatchKeyManaging,
        personDataStore: DetermineStatePersonDataStore,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.chainRegistry = chainRegistry
        self.candidateWallet = candidateWallet
        self.vrfManager = vrfManager
        self.personDataStore = personDataStore
        self.logger = logger
    }
}

extension AirdropService: AirdropServicing {
    func makeProof(for gameInfo: GameInfo) async throws -> GamePallet.AirdropVrfs? {
        guard gameInfo.airdropScheduled else {
            logger.debug(
                "[GameDebug] airdrop.makeProof: gameIndex=\(gameInfo.index) airdropScheduled=false -> no proof"
            )
            return nil
        }

        logger.debug(
            "[GameDebug] airdrop.makeProof: gameIndex=\(gameInfo.index) airdropScheduled=true -> resolving proof"
        )

        let connection = try chainRegistry.getConnectionOrError(for: AppConfig.Chains.usernameChain)
        let runtimeProvider = try chainRegistry.getRuntimeProviderOrError(for: AppConfig.Chains.usernameChain)

        let factory = AirdropProofFactory(
            candidateWallet: candidateWallet,
            personVrfManager: vrfManager,
            proofParamsFetcher: MembershipProofParamsFetcher(
                connection: connection,
                runtimeCodingService: runtimeProvider
            ),
            memberService: GameMemberService(
                connection: connection,
                runtimeService: runtimeProvider
            ),
            membershipStatusChecker: MembershipStatusChecker(
                connection: connection,
                runtimeCodingService: runtimeProvider
            )
        )

        let player: GamePallet.AccountOrPerson =
            if let personData = personDataStore.currentState {
                personData.makeAccountOrPerson()
            } else {
                try .account(accountID: candidateWallet.getRawPublicKey())
            }

        return try await factory.makeProof(gameIndex: gameInfo.index, player: player)
    }

    func subscribeEventStatus(
        forGameIndex gameIndex: GamePallet.GameIndex
    ) -> AsyncStream<NewAirdropPallet.Status?> {
        AsyncStream { continuation in
            let task = Task { [chainRegistry, logger] in
                do {
                    let connection = try chainRegistry.getConnectionOrError(for: AppConfig.Chains.usernameChain)
                    let runtimeProvider = try chainRegistry
                        .getRuntimeProviderOrError(for: AppConfig.Chains.usernameChain)
                    let eventId = NewAirdropPallet.gameEventId(forGameIndex: gameIndex, airdropIndex: 0)
                    let request = BatchStorageSubscriptionRequest(
                        innerRequest: MapSubscriptionRequest(
                            storagePath: NewAirdropPallet.events,
                            localKey: "",
                            keyParamClosure: { BytesCodable(wrappedValue: eventId) }
                        ),
                        mappingKey: AirdropEventStatusSubscriptionResult.Key.event.rawValue
                    )
                    let stream = CallbackBatchStorageSubscription<AirdropEventStatusSubscriptionResult>.asyncStream(
                        requests: [request],
                        connection: connection,
                        runtimeService: runtimeProvider,
                        logger: logger
                    )
                    for try await result in stream {
                        continuation.yield(result.status)
                    }
                    continuation.finish()
                } catch {
                    logger.error("[GameDebug] airdrop.subscribeEventStatus failed gameIndex=\(gameIndex): \(error)")
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
