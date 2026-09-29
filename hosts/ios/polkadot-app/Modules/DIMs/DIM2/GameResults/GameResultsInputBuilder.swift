import Foundation

enum GameResultsInputBuilder {
    struct AttestationsData {
        let score: Int
        let total: Int
        let passed: Bool
        let hashes: [String]
    }

    static func build(
        attestations: AttestationsData,
        member: GameResultsInput.MemberState,
        prize: AirdropPrizeReport?,
        usernameClaim: GameResultsInput.UsernameClaim,
        onPrizeClaim: (() -> Void)? = nil
    ) -> GameResultsInput {
        GameResultsInput(
            attestations: GameResultsInput.Attestations(
                score: attestations.score,
                total: attestations.total,
                passed: attestations.passed
            ),
            member: member,
            prizeDraw: makePrizeDraw(prize: prize),
            usernameClaim: usernameClaim,
            onPrizeClaim: onPrizeClaim,
            attestationHashes: attestations.hashes
        )
    }

    private static func makePrizeDraw(
        prize: AirdropPrizeReport?
    ) -> GameResultsInput.PrizeDraw? {
        guard let prize else {
            Logger.shared.debug("[GameDebug] webviewInput.prizeDraw: nil (no airdrop prize for this game)")
            return nil
        }

        let drawDate = Date(timeIntervalSince1970: TimeInterval(prize.drawTime))
        let nextDrawAt = ISO8601DateFormatter().string(from: drawDate)

        Logger.shared.debug(
            "[GameDebug] webviewInput.prizeDraw: prizeUsd=\(prize.prizeUsd) won=\(prize.won) "
                + "userTicket=\(prize.userTicket) winningTickets=\(prize.winningTickets.count) "
                + "totalEntries=\(prize.totalEntries) ticketDistance=\(prize.ticketDistance) nextDrawAt=\(nextDrawAt)"
        )

        return GameResultsInput.PrizeDraw(
            prizeUsd: prize.prizeUsd,
            userTicket: prize.userTicket,
            winningTickets: prize.winningTickets,
            ticketDistance: prize.ticketDistance,
            totalEntries: prize.totalEntries,
            nextDrawAt: nextDrawAt,
            won: prize.won
        )
    }
}
