package io.paritytech.polkadotapp.feature_videogame_impl.presentation.gameResults

import android.os.Parcelable
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.AirdropClaimParams
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.Attestations
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.GameResultsInput
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.MemberState
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.PrizeDraw
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.UsernameAvailability
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.UsernameClaim
import kotlinx.parcelize.Parcelize
import java.math.BigDecimal

/**
 * Parcelable mirror of [GameResultsInput] for the nav boundary.
 * Kept separate so the data-layer types stay free of `@Parcelize`.
 */
@Parcelize
data class GameResultsPayload(
    val attestations: AttestationsArg,
    val member: MemberStateArg,
    val prizeDraw: PrizeDrawArg?,
    val usernameClaim: UsernameClaimArg,
    /** Ordered matched attestation hashes (hex); streamed via pushAttestation. */
    val attestationHashes: List<String>,
    /** Airdrop claim params captured at build time; reused at claim time (see [GameResultsInput.claim]). */
    val claim: AirdropClaimArg?,
    /** OFF in production (JS `Done` fires `flow.complete`); ON in debug/simulator for an escape hatch. */
    val showTopBar: Boolean
) : Parcelable {
    @Parcelize
    data class AirdropClaimArg(
        val gameIndex: Int,
        val recognized: Boolean
    ) : Parcelable

    @Parcelize
    data class AttestationsArg(
        val score: Int,
        val total: Int,
        val passed: Boolean
    ) : Parcelable

    @Parcelize
    data class MemberStateArg(
        val justBecameMember: Boolean,
        val displayName: String?,
        val memberSince: String?
    ) : Parcelable

    @Parcelize
    data class PrizeDrawArg(
        val prizeUsd: BigDecimal,
        val userTicket: String,
        val winningTickets: List<String>,
        val ticketDistance: Long,
        val totalEntries: Long,
        val nextDrawAt: String,
        val won: Boolean
    ) : Parcelable

    @Parcelize
    data class UsernameClaimArg(
        val eligible: Boolean,
        val suggestedUsername: String?,
        val previousUsername: String?,
        val availability: UsernameAvailability?,
        val alternatives: List<String>?
    ) : Parcelable

    fun toDomain(): GameResultsInput = GameResultsInput(
        attestations = Attestations(
            score = attestations.score,
            total = attestations.total,
            passed = attestations.passed
        ),
        member = MemberState(
            justBecameMember = member.justBecameMember,
            displayName = member.displayName,
            memberSince = member.memberSince
        ),
        prizeDraw = prizeDraw?.let { d ->
            PrizeDraw(
                prizeUsd = d.prizeUsd,
                userTicket = d.userTicket,
                winningTickets = d.winningTickets,
                ticketDistance = d.ticketDistance,
                totalEntries = d.totalEntries,
                nextDrawAt = d.nextDrawAt,
                won = d.won
            )
        },
        usernameClaim = UsernameClaim(
            eligible = usernameClaim.eligible,
            suggestedUsername = usernameClaim.suggestedUsername,
            previousUsername = usernameClaim.previousUsername,
            availability = usernameClaim.availability,
            alternatives = usernameClaim.alternatives
        ),
        attestationHashes = attestationHashes,
        claim = claim?.let { AirdropClaimParams(gameIndex = it.gameIndex, recognized = it.recognized) }
    )

    companion object {
        fun from(input: GameResultsInput, showTopBar: Boolean = false) = GameResultsPayload(
            attestations = AttestationsArg(
                score = input.attestations.score,
                total = input.attestations.total,
                passed = input.attestations.passed
            ),
            member = MemberStateArg(
                justBecameMember = input.member.justBecameMember,
                displayName = input.member.displayName,
                memberSince = input.member.memberSince
            ),
            prizeDraw = input.prizeDraw?.let { d ->
                PrizeDrawArg(
                    prizeUsd = d.prizeUsd,
                    userTicket = d.userTicket,
                    winningTickets = d.winningTickets,
                    ticketDistance = d.ticketDistance,
                    totalEntries = d.totalEntries,
                    nextDrawAt = d.nextDrawAt,
                    won = d.won
                )
            },
            usernameClaim = UsernameClaimArg(
                eligible = input.usernameClaim.eligible,
                suggestedUsername = input.usernameClaim.suggestedUsername,
                previousUsername = input.usernameClaim.previousUsername,
                availability = input.usernameClaim.availability,
                alternatives = input.usernameClaim.alternatives
            ),
            attestationHashes = input.attestationHashes,
            claim = input.claim?.let { AirdropClaimArg(gameIndex = it.gameIndex, recognized = it.recognized) },
            showTopBar = showTopBar
        )
    }
}
