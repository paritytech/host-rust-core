package io.paritytech.polkadotapp.feature_videogame_impl.data.tracked

import io.paritytech.polkadotapp.chains.storage.source.query.intercept.StorageObserveRequest
import io.paritytech.polkadotapp.chains.storage.source.query.intercept.StorageQueryInterceptor
import io.paritytech.polkadotapp.chains.storage.source.query.intercept.StorageQueryRequest
import io.paritytech.polkadotapp.chains.storage.source.query.intercept.StorageTarget
import io.paritytech.polkadotapp.chains.storage.source.query.intercept.valueAs
import io.paritytech.polkadotapp.chains.util.Modules
import io.paritytech.polkadotapp.feature_transactions.api.data.tracked.ActiveTrackedExtrinsic
import io.paritytech.polkadotapp.feature_transactions.api.data.tracked.TrackedExtrinsicService
import io.paritytech.polkadotapp.feature_transactions.api.data.tracked.getLatestActive
import io.paritytech.polkadotapp.feature_transactions.api.data.tracked.observeLatestActive
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainGamePlayerCredibility
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainVideoGamePlayerInfo
import io.paritytech.polkadotapp.feature_videogame_impl.domain.tracked.VideoGameExtrinsicTags
import io.paritytech.polkadotapp.feature_videogame_impl.domain.tracked.VideoGamePlayerOverrideTarget
import io.paritytech.polkadotapp.feature_videogame_impl.domain.tracked.decodeOverrideTargetOrNull
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import timber.log.Timber
import javax.inject.Inject

/**
 * Makes an in-flight vote/registration visible in `VideoGame.Players` reads before the chain catches up.
 * For the read's player key it ORs `sentReport`/`registered` from any active vote/register tx whose recorded
 * [VideoGamePlayerOverrideTarget] matches that key — synthesizing a slim player row when the chain has none yet.
 * Scoping is purely by matching `target.playerStorageKey` to the read key; the tag suffix is never parsed.
 */
class LocalTxOverrideInterceptor @Inject constructor(
    private val trackedExtrinsicService: TrackedExtrinsicService,
) : StorageQueryInterceptor {
    override val targets: Set<StorageTarget> = setOf(StorageTarget(Modules.VIDEO_GAME, "Players"))

    override suspend fun <T> interceptQuery(request: StorageQueryRequest<T>): T {
        val vote = trackedExtrinsicService.getLatestActive(VideoGameExtrinsicTags.VOTE_PREFIX)
        val register = trackedExtrinsicService.getLatestActive(VideoGameExtrinsicTags.REGISTER_PREFIX)

        @Suppress("UNCHECKED_CAST")
        return applyOverride(request.valueAs(), request.storageKey, vote, register) as T
    }

    override fun <T> interceptObserve(request: StorageObserveRequest<T>): Flow<T> {
        return combine(
            request.downstream,
            trackedExtrinsicService.observeLatestActive(VideoGameExtrinsicTags.VOTE_PREFIX),
            trackedExtrinsicService.observeLatestActive(VideoGameExtrinsicTags.REGISTER_PREFIX),
        ) { chainValue, vote, register ->
            @Suppress("UNCHECKED_CAST")
            applyOverride(chainValue as OnChainVideoGamePlayerInfo?, request.storageKey, vote, register) as T
        }
    }

    private fun applyOverride(
        chainValue: OnChainVideoGamePlayerInfo?,
        storageKey: String,
        vote: ActiveTrackedExtrinsic?,
        register: ActiveTrackedExtrinsic?,
    ): OnChainVideoGamePlayerInfo? {
        val sentReportOverride = vote.targetsKey(storageKey)
        val registeredOverride = register.targetsKey(storageKey)

        if (!sentReportOverride && !registeredOverride) {
            Timber.d("No override for Players")
            return chainValue
        }

        if (chainValue == null) {
            val gameIndex = register.targetGameIndex(storageKey) ?: vote.targetGameIndex(storageKey) ?: return null

            return OnChainVideoGamePlayerInfo(
                firstGame = gameIndex,
                registered = registeredOverride,
                sentReport = sentReportOverride,
                earlyAttendanceEnactment = null,
                yesPerson = 0,
                noNotPerson = 0,
                expectedMaxVoteWeight = 0,
                voteWeight = 0,
                credibility = OnChainGamePlayerCredibility.Invited,
            ).also {
                Timber.d("Synthesize Players from in-flight tx: $it")
            }
        }

        val overridden = OnChainVideoGamePlayerInfo(
            firstGame = chainValue.firstGame,
            registered = chainValue.registered || registeredOverride,
            sentReport = chainValue.sentReport || sentReportOverride,
            earlyAttendanceEnactment = chainValue.earlyAttendanceEnactment,
            yesPerson = chainValue.yesPerson,
            noNotPerson = chainValue.noNotPerson,
            expectedMaxVoteWeight = chainValue.expectedMaxVoteWeight,
            voteWeight = chainValue.voteWeight,
            credibility = chainValue.credibility,
        )

        logOverride(chainValue, overridden)

        return overridden
    }

    private fun ActiveTrackedExtrinsic?.targetsKey(storageKey: String): Boolean = target(storageKey) != null

    private fun ActiveTrackedExtrinsic?.targetGameIndex(storageKey: String): GameIndex? = target(storageKey)?.gameIndex

    private fun ActiveTrackedExtrinsic?.target(storageKey: String): VideoGamePlayerOverrideTarget? {
        return this?.additional?.decodeOverrideTargetOrNull()
            ?.takeIf { it.playerStorageKey == storageKey }
    }

    // Only when the override actually flips a flag — a no-op OR (chain already true) stays silent.
    private fun logOverride(chain: OnChainVideoGamePlayerInfo, overridden: OnChainVideoGamePlayerInfo) {
        if (overridden.registered == chain.registered && overridden.sentReport == chain.sentReport) return
        Timber.d("Override Players: registered ${chain.registered}->${overridden.registered}, sentReport ${chain.sentReport}->${overridden.sentReport}")
    }
}
