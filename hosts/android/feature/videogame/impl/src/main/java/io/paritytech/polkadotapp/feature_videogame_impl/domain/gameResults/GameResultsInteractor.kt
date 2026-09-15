package io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getDepositAccount
import io.paritytech.polkadotapp.feature_chain_resources_api.data.repository.ResourcesRepository
import io.paritytech.polkadotapp.feature_chain_resources_api.domain.model.ConsumerInfo
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.model.UpgradeUsernameAvailabilityState
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.usecase.CheckUsernameAvailabilityUseCase
import io.paritytech.polkadotapp.feature_usernames_api.domain.model.Username
import io.paritytech.polkadotapp.feature_usernames_api.domain.usecase.UsernameOfAccountUseCase
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.data.hex
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAccountOrPerson
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.isRecognized
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.ScoreRepository
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameRepositoryInternal
import io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase.PlayingAccountUseCase
import kotlinx.coroutines.flow.Flow
import timber.log.Timber
import javax.inject.Inject

internal const val PASS_THRESHOLD = 6

/**
 * Game-results screen interactor. `attestations`, `member`, `usernameClaim` and `prizeDraw`
 * are chain-driven; when the chain context is unreadable the payload degrades to an empty
 * not-passed result (no mock data in production).
 *
 * Attestations come from the on-chain matchmaking roster ([GameGroupRosterService]) plus
 * Fast Attendance: `passed` is the chain-authoritative
 * `Player.early_attendance_enactment.attendance` (not passed while the enactment isn't
 * cached — no score heuristic).
 *
 * A pass streams the full deterministic candidate set up front. The on-chain context that drives
 * all this is resolved by [AttestationContextResolver]; for a game still unresolved at open,
 * [GameResultsLiveUpdater] keeps the screen current via [subscribeLiveResults].
 * [resolveUsernameAvailability] is the async answer to `flow.username_availability_needed`.
 */
interface GameResultsInteractor {
    context(scope: ComputationalScope)
    suspend fun buildGameResults(): GameResultsInput

    context(scope: ComputationalScope)
    fun subscribeLiveResults(initialInput: GameResultsInput): Flow<GameResultsLiveEvent>

    context(scope: ComputationalScope)
    suspend fun resolveUsernameAvailability(name: String): UsernameAvailability

    context(scope: ComputationalScope)
    suspend fun claimAirdropPrize(claim: AirdropClaimParams?): Result<Unit>
}

class RealGameResultsInteractor @Inject constructor(
    private val playingAccountUseCase: PlayingAccountUseCase,
    private val accountRepository: AccountRepository,
    private val chainRegistry: ChainRegistry,
    private val resourcesRepository: ResourcesRepository,
    private val videoGameRepository: VideoGameRepositoryInternal,
    private val airdropPrizeService: AirdropPrizeService,
    private val reportSnapshot: GameReportSnapshot,
    private val usernameOfAccountUseCase: UsernameOfAccountUseCase,
    private val scoreRepository: ScoreRepository,
    private val checkUsernameAvailabilityUseCase: CheckUsernameAvailabilityUseCase,
    private val attestationContextResolver: AttestationContextResolver,
    private val gameResultsLiveUpdater: GameResultsLiveUpdater,
) : GameResultsInteractor {
    context(scope: ComputationalScope)
    override suspend fun buildGameResults(): GameResultsInput {
        val consumer = currentConsumerInfoOrNull()
        val localUsername = usernameOfAccountUseCase.getUsername()
            .logFailure("[GameResults] stored username lookup failed")
            .getOrNull()?.username
        val context = runCatching { attestationContextResolver.resolve() }
            .onFailure { Timber.w(it, "[GameResults] attestation context unavailable; degrading to empty result") }
            .getOrNull()
        val chainAttestations = context?.let { resolveAttestations(it) }
        val isMemberNow = context?.let { isMember(it.chainId, it.attestee) } ?: false

        val reportSnap = reportSnapshot.current()
        val wasNotMemberBefore = !(reportSnap?.wasRegistered ?: true)
        val member = resolveMember(consumer, localUsername, justBecameMember = wasNotMemberBefore && isMemberNow)

        Timber.d(
            "[Airdrop] member(build): snapshotPresent=${reportSnap != null} " +
                "wasRegistered=${reportSnap?.wasRegistered} isMemberNow=$isMemberNow " +
                "→ justBecameMember=${member.justBecameMember}"
        )

        return GameResultsInput(
            attestations = chainAttestations?.attestations
                ?: Attestations(score = 0, total = ATTESTATION_TOTAL, passed = false),
            member = member,
            prizeDraw = resolvePrizeDraw(context, chainAttestations, isMember = isMemberNow || wasNotMemberBefore),
            usernameClaim = resolveUsernameClaim(consumer, localUsername),
            attestationHashes = chainAttestations?.hashes.orEmpty(),
            // Capture claim params now, while the context is resolvable — reused at claim time.
            claim = context?.let {
                AirdropClaimParams(
                    gameIndex = it.gameIndex.value,
                    recognized = it.attestee is OnChainAccountOrPerson.Person
                )
            },
        )
    }

    context(scope: ComputationalScope)
    override fun subscribeLiveResults(initialInput: GameResultsInput): Flow<GameResultsLiveEvent> =
        gameResultsLiveUpdater.liveResults(initialInput)

    context(scope: ComputationalScope)
    override suspend fun claimAirdropPrize(claim: AirdropClaimParams?): Result<Unit> {
        // Use the params captured when the context resolved at results-build time — NOT a fresh
        // resolve. By claim time the game is over, so re-resolving the roster/player returns null and
        // the claim is silently dropped. iOS avoids this by claiming from the captured report context.
        claim ?: return Result.failure(IllegalStateException("airdrop claim: no captured claim params"))

        val chain = chainRegistry.peopleChain()
        // Beneficiary is the deposit account so the prize asset lands where AutoConvertDepositService
        // watches and onboards it into Coinage (a raw balance in the candidate account isn't usable in
        // the Pocket). This is independent of the signing origin below.
        val beneficiary = accountRepository.getDepositAccount().accountIdIn(chain)

        Timber.d("[Airdrop] claim: game=${claim.gameIndex} recognized=${claim.recognized}")
        return videoGameRepository.claimAirdrop(chain, GameIndex(claim.gameIndex), beneficiary, claim.recognized)
            .onSuccess { Timber.d("[Airdrop] claim OK game=${claim.gameIndex}") }
            .onFailure { Timber.e(it, "[Airdrop] claim FAILED game=${claim.gameIndex}") }
    }

    // Prefer the on-chain consumer; fall back to a locally-claimed username not yet on chain.
    private fun resolveMember(
        consumer: ConsumerInfo?,
        localUsername: Username?,
        justBecameMember: Boolean,
    ): MemberState {
        return MemberState(
            justBecameMember = justBecameMember,
            displayName = consumer?.username ?: localUsername?.getDisplayUsername(),
            memberSince = null,
        )
    }

    private suspend fun resolveAttestations(context: AttestationContext): ChainAttestations {
        // `total` is the fixed attestation pack size (the webview's shelf), not the round count.
        val total = ATTESTATION_TOTAL

        val minted = videoGameRepository
            .getMintedNftHashes(context.chainId, at = null, owner = context.attestee, candidateHashes = context.candidates.hashes)
            .logFailure("[GameResults] minted-NFT read failed; streaming none")
            .getOrNull()
            .orEmpty()
        val realHashes = context.candidates.hashes.filter { it in minted }.distinct().take(total)

        val passed = realHashes.size >= PASS_THRESHOLD
        val score = minOf(realHashes.size, total)

        val packHashes = if (passed && realHashes.size < total) {
            val pending = videoGameRepository
                .getPendingNftHashes(context.chainId, at = null, owner = context.attestee)
                .logFailure("[GameResults] pending-NFT read failed; completing from stream")
                .getOrNull()
                .orEmpty()
            (realHashes + pending.filter { it !in realHashes }).distinct().take(total)
        } else {
            realHashes
        }
        val streamedHashes = packHashes.map { it.hex() }

        return ChainAttestations(
            attestations = Attestations(score = score, total = total, passed = passed),
            hashes = streamedHashes,
        )
    }

    // Prize draw only when the player passed AND is a member.
    private suspend fun resolvePrizeDraw(
        context: AttestationContext?,
        attestations: ChainAttestations?,
        isMember: Boolean,
    ): PrizeDraw? {
        if (context == null || attestations?.attestations?.passed != true || !isMember) return null
        return airdropPrizeService.fetchPrizeDraw(context.chainId, context.gameIndex, context.attestee)
            .logFailure("[GameResults] prize-draw read failed")
            .getOrNull()
    }

    // Only a lite (suffixed) handle is claimable — the prompt offers the upgrade to a full name.
    // A full username already is the target, so it's not eligible. Prefer the on-chain consumer,
    // else the locally-claimed username.
    private fun resolveUsernameClaim(consumer: ConsumerInfo?, localUsername: Username?): UsernameClaim = when {
        consumer != null -> {
            val full = consumer.fullUsername
            val lite = consumer.liteUsername
            val suggested = lite.substringBeforeLast('.', missingDelimiterValue = lite)
            UsernameClaim(
                eligible = full == null,
                suggestedUsername = if (full == null) suggested else null,
                previousUsername = full ?: lite,
                // Resolved async via flow.username_availability_needed → setUsernameAvailability.
                availability = null,
                alternatives = null,
            )
        }

        localUsername != null -> UsernameClaim(
            eligible = localUsername.index != null,
            suggestedUsername = localUsername.base.takeIf { localUsername.index != null },
            previousUsername = localUsername.getDisplayUsername(),
            availability = null,
            alternatives = null,
        )

        else -> UsernameClaim(
            eligible = false,
            suggestedUsername = null,
            previousUsername = null,
            availability = null,
            alternatives = null,
        )
    }

    context(scope: ComputationalScope)
    override suspend fun resolveUsernameAvailability(name: String): UsernameAvailability {
        return checkUsernameAvailabilityUseCase(name)
            .logFailure("[GameResults] username availability lookup failed for '$name'")
            .map { it.toAvailability() }
            .getOrDefault(UsernameAvailability.UNKNOWN)
    }

    private fun UpgradeUsernameAvailabilityState.toAvailability(): UsernameAvailability = when (this) {
        UpgradeUsernameAvailabilityState.NotAvailable -> UsernameAvailability.TAKEN
        UpgradeUsernameAvailabilityState.Free,
        UpgradeUsernameAvailabilityState.ReservedByUs -> UsernameAvailability.AVAILABLE
    }

    private suspend fun isMember(chainId: ChainId, player: OnChainAccountOrPerson): Boolean {
        val participant = scoreRepository.getParticipantFresh(chainId, player)
            .logFailure("[GameResults] member participant read failed")
            .getOrNull() ?: return false
        return participant.recognition.isRecognized() || participant.reachedPersonhoodLastAttendance
    }

    context(scope: ComputationalScope)
    private suspend fun currentConsumerInfoOrNull() = runCatching {
        val account = playingAccountUseCase.getOurPlayerAccountId()
        val chainId = chainRegistry.peopleChain().id
        resourcesRepository.consumerInfo(chainId, account)
            .logFailure("[GameResults] consumer-info read failed")
            .getOrNull()
    }.onFailure {
        Timber.w(it, "[GameResults] consumer-info lookup failed")
    }.getOrNull()

    private data class ChainAttestations(val attestations: Attestations, val hashes: List<String>)

    private companion object {
        // Fixed attestation pack size (the webview's shelf), not the chain round count.
        const val ATTESTATION_TOTAL = 10
    }
}
