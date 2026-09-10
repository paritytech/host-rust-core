package io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_videogame_impl.data.AttestationNftHash
import io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults.GameNftsSubscriptionService
import io.paritytech.polkadotapp.feature_videogame_impl.data.hex
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAccountOrPerson
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.isRecognized
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.ScoreRepository
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameRepositoryInternal
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.flow
import timber.log.Timber
import javax.inject.Inject

/**
 * Post-open live phase of the results screen. A game still unresolved at open keeps the screen
 * current: late mints stream in, and — since mints land in the block that finalises attendance —
 * each one triggers a verdict re-check, upgrading the screen to passed mid-stream when it confirms
 * (mirrors the iOS interactor).
 */
class GameResultsLiveUpdater @Inject constructor(
    private val attestationContextResolver: AttestationContextResolver,
    private val gameNftsSubscriptionService: GameNftsSubscriptionService,
    private val videoGameRepository: VideoGameRepositoryInternal,
    private val airdropPrizeService: AirdropPrizeService,
    private val scoreRepository: ScoreRepository,
    private val reportSnapshot: GameReportSnapshot,
) {
    context(scope: ComputationalScope)
    fun liveResults(initialInput: GameResultsInput): Flow<GameResultsLiveEvent> = flow {
        val context = runCatching { attestationContextResolver.resolve() }
            .onFailure { Timber.w(it, "[GameResults] live-results subscription setup failed") }
            .getOrNull() ?: return@flow

        val total = initialInput.attestations.total
        val alreadyStreamed = initialInput.attestationHashes.toSet()
        // Dedup on the raw hash bytes, not the hex string (cheaper, no per-event re-encoding).
        val pushed = context.candidates.hashes
            .filter { it.hex() in alreadyStreamed }
            .toMutableSet()
        var upgraded = initialInput.attestations.passed

        gameNftsSubscriptionService
            .newlyMintedHashes(context.chainId, context.attestee, context.candidates.hashes)
            .collect { minted ->
                if (pushed.add(minted)) {
                    emit(GameResultsLiveEvent.AttestationMinted(minted.hex()))
                }
                // Pass = the real streamed count crossing the threshold; complete + deliver then.
                if (!upgraded && pushed.size >= PASS_THRESHOLD) {
                    upgraded = true
                    emit(upgradeToPassed(context, initialInput, pushed, total))
                }
            }
    }.catch { Timber.w(it, "[GameResults] live results stream failed") }

    private suspend fun upgradeToPassed(
        context: AttestationContext,
        initialInput: GameResultsInput,
        pushed: Set<AttestationNftHash>,
        total: Int,
    ): GameResultsLiveEvent.UpgradedToPassed {
        val score = minOf(pushed.size, total)
        val padCount = (total - pushed.size).coerceAtLeast(0)
        val padReal = if (padCount > 0) {
            videoGameRepository.getPendingNftHashes(context.chainId, at = null, owner = context.attestee)
                .logFailure("[GameResults] pending-NFT read failed; completing from stream")
                .getOrNull().orEmpty()
                .filter { it !in pushed }.distinct().take(padCount)
        } else {
            emptyList()
        }
        val padHashes = padReal.map { it.hex() }

        val isMemberNow = isMember(context.chainId, context.attestee)
        val reportSnap = reportSnapshot.current()
        val wasNotMemberBefore = !(reportSnap?.wasRegistered ?: true)

        Timber.d(
            "[Airdrop] member(upgrade): snapshotPresent=${reportSnap != null} " +
                "wasRegistered=${reportSnap?.wasRegistered} isMemberNow=$isMemberNow " +
                "→ justBecameMember=${wasNotMemberBefore && isMemberNow}"
        )
        return GameResultsLiveEvent.UpgradedToPassed(
            input = initialInput.copy(
                attestations = Attestations(score = score, total = total, passed = true),
                prizeDraw = prizeDrawIfMember(context, eligible = isMemberNow || wasNotMemberBefore),
                member = initialInput.member.copy(justBecameMember = wasNotMemberBefore && isMemberNow),
                attestationHashes = pushed.map { it.hex() } + padHashes,
                // Capture claim params from the live-resolved context — covers games unresolved at open.
                claim = AirdropClaimParams(
                    gameIndex = context.gameIndex.value,
                    recognized = context.attestee is OnChainAccountOrPerson.Person
                ),
            ),
            padHashes = padHashes,
        )
    }

    private suspend fun prizeDrawIfMember(context: AttestationContext, eligible: Boolean): PrizeDraw? {
        if (!eligible) return null
        return airdropPrizeService.fetchPrizeDraw(context.chainId, context.gameIndex, context.attestee)
            .logFailure("[GameResults] prize-draw read failed")
            .getOrNull()
    }

    private suspend fun isMember(chainId: ChainId, player: OnChainAccountOrPerson): Boolean {
        val participant = scoreRepository.getParticipantFresh(chainId, player)
            .logFailure("[GameResults] member participant read failed")
            .getOrNull() ?: return false
        return participant.recognition.isRecognized() || participant.reachedPersonhoodLastAttendance
    }
}
