import Foundation
import BigInt
import SubstrateSdk
import SubstrateStorageQuery
import StructuredConcurrency
import Individuality

protocol AirdropPrizeServicing {
    func fetchReport(
        gameIndex: UInt32,
        player: GamePallet.AccountOrPerson,
        blockHash: Data?
    ) async throws -> AirdropPrizeReport?
}

final class AirdropPrizeService: AirdropPrizeServicing {
    private let connection: JSONRPCEngine
    private let runtimeService: RuntimeCodingServiceProtocol
    /// Precision of the prize asset. We assume the prize is paid in `AppConfig.Assets.mainAsset` and
    /// take its precision from the chain registry, instead of decoding it from the prize XCM Location.
    private let prizeAssetPrecision: UInt16
    private let requestFactory = StorageRequestFactory.asyncInit()

    init(
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        prizeAssetPrecision: UInt16
    ) {
        self.connection = connection
        self.runtimeService = runtimeService
        self.prizeAssetPrecision = prizeAssetPrecision
    }

    func fetchReport(
        gameIndex: UInt32,
        player: GamePallet.AccountOrPerson,
        blockHash: Data?
    ) async throws -> AirdropPrizeReport? {
        let codingFactory = try await runtimeService.fetchCoderFactoryOperation().asyncExecute()
        let eventId = NewAirdropPallet.gameEventId(forGameIndex: gameIndex, airdropIndex: 0)
        Logger.shared
            .debug(
                "[GameDebug] airdrop.fetchReport start gameIndex=\(gameIndex) eventId=\(eventId.toHex()) " +
                    "blockHash=\(blockHash?.toHex() ?? "head") player=\(player.rawTypeValue)"
            )

        guard let event = try await fetchEvent(
            eventId: eventId,
            codingFactory: codingFactory,
            blockHash: blockHash
        ) else {
            Logger.shared.debug("[GameDebug] airdrop.fetchReport: no active event found for eventId=\(eventId.toHex())")
            return nil
        }
        Logger.shared
            .debug(
                "[GameDebug] airdrop.event found assetIdRaw=\(event.info.prize.assetId) " +
                    "amount=\(event.info.prize.assetAmount) drawTime=\(event.info.drawTime) " +
                    "totalParticipants=\(String(describing: event.status.totalParticipants)) " +
                    "prizeAssetPrecision=\(prizeAssetPrecision) (assumed mainAsset)"
            )

        async let registrationsTask = fetchRegistrations(
            eventId: eventId,
            codingFactory: codingFactory,
            blockHash: blockHash
        )
        async let winnersTask = fetchWinners(
            eventId: eventId,
            codingFactory: codingFactory,
            blockHash: blockHash
        )
        let registrations = try await registrationsTask
        let winners = try await winnersTask
        let decimals = prizeAssetPrecision
        Logger.shared
            .debug(
                "[GameDebug] airdrop reads done registrations=\(registrations.count) " +
                    "winners=\(winners.count) decimals=\(decimals)"
            )

        let report = makeReport(
            event: event,
            registrations: registrations,
            winners: winners,
            decimals: decimals,
            player: player
        )
        Logger.shared
            .debug(
                "[GameDebug] airdrop report prizeUsd=\(report.prizeUsd) won=\(report.won) " +
                    "userTicket=\(report.userTicket) winningTickets=\(report.winningTickets.count) " +
                    "totalEntries=\(report.totalEntries)"
            )
        return report
    }
}

private extension AirdropPrizeService {
    func fetchEvent(
        eventId: Data,
        codingFactory: RuntimeCoderFactoryProtocol,
        blockHash: Data?
    ) async throws -> NewAirdropPallet.ActiveEvent? {
        let responses: [StorageResponse<NewAirdropPallet.ActiveEvent>] = try await requestFactory.queryItems(
            engine: connection,
            keyParams: { [BytesCodable(wrappedValue: eventId)] },
            factory: { codingFactory },
            storagePath: NewAirdropPallet.events,
            at: blockHash
        )
        .asyncExecute()

        return responses.first?.value
    }

    func fetchRegistrations(
        eventId: Data,
        codingFactory: RuntimeCoderFactoryProtocol,
        blockHash: Data?
    ) async throws -> [NewAirdropPallet.RegistrationsKey: NewAirdropPallet.RegistrationEntry] {
        try await requestFactory.queryByPrefix(
            engine: connection,
            request: MapRemoteStorageRequest(storagePath: NewAirdropPallet.registrations) {
                BytesCodable(wrappedValue: eventId)
            },
            storagePath: NewAirdropPallet.registrations,
            factory: { codingFactory },
            options: StorageQueryListOptions(atBlock: blockHash)
        )
        .asyncExecute()
    }

    func fetchWinners(
        eventId: Data,
        codingFactory: RuntimeCoderFactoryProtocol,
        blockHash: Data?
    ) async throws -> [NewAirdropPallet.WinnersKey: BytesCodable] {
        try await requestFactory.queryByPrefix(
            engine: connection,
            request: MapRemoteStorageRequest(storagePath: NewAirdropPallet.winners) {
                BytesCodable(wrappedValue: eventId)
            },
            storagePath: NewAirdropPallet.winners,
            factory: { codingFactory },
            options: StorageQueryListOptions(atBlock: blockHash)
        )
        .asyncExecute()
    }
}

private extension AirdropPrizeService {
    func makeReport(
        event: NewAirdropPallet.ActiveEvent,
        registrations: [NewAirdropPallet.RegistrationsKey: NewAirdropPallet.RegistrationEntry],
        winners: [NewAirdropPallet.WinnersKey: BytesCodable],
        decimals: UInt16,
        player: GamePallet.AccountOrPerson
    ) -> AirdropPrizeReport {
        let userTicketData = registrations
            .first { entryMatches($0.value, player: player) }?
            .key.ticket

        let winningTicketData = winners.values.map(\.wrappedValue)
        let won = winners.keys.contains { entryMatches($0.entry, player: player) }
        let totalEntries = event.status.totalParticipants.map(Int.init) ?? registrations.count

        return AirdropPrizeReport(
            prizeUsd: makePrizeUsd(amount: event.info.prize.assetAmount, decimals: decimals),
            userTicket: userTicketData?.toHex() ?? "",
            winningTickets: winningTicketData.map { $0.toHex() },
            ticketDistance: won ? 0 : 1,
            totalEntries: totalEntries,
            drawTime: event.info.drawTime,
            won: won
        )
    }

    func entryMatches(
        _ entry: NewAirdropPallet.RegistrationEntry,
        player: GamePallet.AccountOrPerson
    ) -> Bool {
        switch (entry, player) {
        case let (.account(accountId), .account(playerAccountId)):
            accountId == playerAccountId
        case let (.alias(participantOrigin), .person(alias)):
            participantOrigin == alias
        default:
            false
        }
    }

    func makePrizeUsd(amount: BigUInt, decimals: UInt16) -> Decimal {
        Decimal.fromSubstrateAmount(amount, precision: Int16(decimals)) ?? 0
    }
}
