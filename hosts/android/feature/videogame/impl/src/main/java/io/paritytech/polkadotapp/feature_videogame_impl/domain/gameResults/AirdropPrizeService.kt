package io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults

import io.novasama.substrate_sdk_android.extensions.toHexString
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.network.binding.intoBalance
import io.paritytech.polkadotapp.chains.util.amountFromPlanks
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.flatMapNotNull
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults.AirdropEventId
import io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults.AirdropRepository
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAccountOrPerson
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainActiveEvent
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAirdropPrize
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAirdropRegistrationEntry
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.totalParticipants
import timber.log.Timber
import java.time.Instant
import javax.inject.Inject

/**
 * Aggregates the weekly prize-draw block from pallet-airdrop reads.
 * Success with `null` means the game has no airdrop event; failures propagate
 * so the caller can log and fall back.
 */
class AirdropPrizeService @Inject constructor(
    private val airdropRepository: AirdropRepository,
) {
    suspend fun fetchPrizeDraw(
        chainId: ChainId,
        gameIndex: GameIndex,
        attestee: OnChainAccountOrPerson,
    ): Result<PrizeDraw?> {
        val eventId = AirdropEventId.fromGameIndex(gameIndex)
        return airdropRepository.getActiveEvent(chainId, eventId).flatMapNotNull { event ->
            buildPrizeDraw(chainId, eventId, event, attestee)
        }.onFailure { Timber.e(it, "[Airdrop] fetchPrizeDraw FAILED for game=${gameIndex.value}") }
    }

    private suspend fun buildPrizeDraw(
        chainId: ChainId,
        eventId: AirdropEventId,
        event: OnChainActiveEvent,
        attestee: OnChainAccountOrPerson,
    ): Result<PrizeDraw> {
        return airdropRepository.getRegistrations(chainId, eventId).flatMap { registrations ->
            airdropRepository.getWinners(chainId, eventId).flatMap { winners ->
                resolveDecimals(chainId, event.info.prize).map { decimals ->
                    buildPrizeDraw(event, registrations, winners, attestee, decimals)
                }
            }
        }
    }

    // The runtime's Assets instance is keyed by the prize's XCM Location itself; resolve its
    // decimals to scale the amount. Fail closed when the metadata is unavailable: an unresolved
    // decimals would render the prize at the wrong magnitude, which is worse than no prize — the
    // caller maps the failure to "no draw".
    private suspend fun resolveDecimals(chainId: ChainId, prize: OnChainAirdropPrize): Result<Int> {
        return airdropRepository.getAssetDecimals(chainId, prize.assetId).mapCatching { decimals ->
            requireNotNull(decimals) { "no asset metadata for ${prize.assetId}" }
        }
    }

    private fun buildPrizeDraw(
        event: OnChainActiveEvent,
        registrations: Map<DataByteArray, OnChainAirdropRegistrationEntry>,
        winners: Map<OnChainAirdropRegistrationEntry, DataByteArray>,
        attestee: OnChainAccountOrPerson,
        decimals: Int,
    ): PrizeDraw {
        val userTicket = registrations.entries
            .firstOrNull { (_, entry) -> entry.matches(attestee) }
            ?.key?.value?.toHexString(withPrefix = false)
            .orEmpty()
        val winningTickets = winners.values.map { it.value.toHexString(withPrefix = false) }
        val won = winners.keys.any { it.matches(attestee) }
        val totalEntries = (event.status.totalParticipants ?: registrations.size).toLong()

        return PrizeDraw(
            prizeUsd = event.info.prize.assetAmount.intoBalance().amountFromPlanks(decimals),
            userTicket = userTicket,
            winningTickets = winningTickets,
            // No on-chain distance metric; 0 when won, 1 otherwise.
            ticketDistance = if (won) 0L else 1L,
            totalEntries = totalEntries,
            nextDrawAt = Instant.ofEpochSecond(event.info.drawTime).toString(),
            won = won,
        )
    }

    private fun OnChainAirdropRegistrationEntry.matches(attestee: OnChainAccountOrPerson): Boolean = when {
        this is OnChainAirdropRegistrationEntry.Account && attestee is OnChainAccountOrPerson.Account ->
            accountId == attestee.accountId
        this is OnChainAirdropRegistrationEntry.Alias && attestee is OnChainAccountOrPerson.Person ->
            participantOrigin.value contentEquals attestee.alias.value
        else -> false
    }
}
