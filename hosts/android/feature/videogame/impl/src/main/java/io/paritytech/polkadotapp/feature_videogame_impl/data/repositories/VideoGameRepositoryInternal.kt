package io.paritytech.polkadotapp.feature_videogame_impl.data.repositories

import io.novasama.substrate_sdk_android.hash.Hasher.blake2b256
import io.novasama.substrate_sdk_android.runtime.definitions.types.generics.MultiSignature
import io.paritytech.polkadotapp.chains.call.MultiChainRuntimeCallsApi
import io.paritytech.polkadotapp.chains.call.RuntimeCallsApi
import io.paritytech.polkadotapp.chains.di.LocalSourceQualifier
import io.paritytech.polkadotapp.chains.di.RemoteSourceQualifier
import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainAssetWithAmount
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.withAmount
import io.paritytech.polkadotapp.chains.multiNetwork.withRuntime
import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.chains.network.binding.BlockHash
import io.paritytech.polkadotapp.chains.network.binding.bindBalance
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.chains.storage.source.query.AtBlock
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.chains.storage.source.query.toAtBlock
import io.paritytech.polkadotapp.chains.storage.source.queryCatching
import io.paritytech.polkadotapp.common.data.memory.ComputationalCache
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.data.memory.useSharedFlow
import io.paritytech.polkadotapp.common.domain.model.AccountEcdhKey
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.common.domain.model.EncodedPublicKey
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.common.utils.*
import io.paritytech.polkadotapp.common.utils.scale.encodeOnChain
import io.paritytech.polkadotapp.common.utils.scale.toDomain
import io.paritytech.polkadotapp.common.utils.scale.toScale
import io.paritytech.polkadotapp.database.dao.VideoGameVoteDao
import io.paritytech.polkadotapp.feature_balances_api.data.type.TokenBalanceTypeRegistry
import io.paritytech.polkadotapp.feature_people_api.data.signer.origins.PeopleOrigins
import io.paritytech.polkadotapp.feature_people_api.domain.invitation.IssuedInvitation
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonalAlias
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicService
import io.paritytech.polkadotapp.feature_transactions.api.data.FormExtrinsic
import io.paritytech.polkadotapp.feature_transactions.api.data.Mortality
import io.paritytech.polkadotapp.feature_transactions.api.data.flattenExecutionFailure
import io.paritytech.polkadotapp.feature_transactions.api.data.origins.SignedOrigins
import io.paritytech.polkadotapp.feature_transactions.api.data.tracked.TrackedExtrinsicService
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.TransactionOrigin
import io.paritytech.polkadotapp.feature_videogame_api.data.repositories.VideoGameRepository
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.data.AttestationNftHash
import io.paritytech.polkadotapp.feature_videogame_impl.data.ScoreContextProvider
import io.paritytech.polkadotapp.feature_videogame_impl.data.airdrop.toAirdropVrf
import io.paritytech.polkadotapp.feature_videogame_impl.data.aliasToStmtAccount
import io.paritytech.polkadotapp.feature_videogame_impl.data.archivedPlayers
import io.paritytech.polkadotapp.feature_videogame_impl.data.claimAirdrop
import io.paritytech.polkadotapp.feature_videogame_impl.data.communicationIdentifiers
import io.paritytech.polkadotapp.feature_videogame_impl.data.game
import io.paritytech.polkadotapp.feature_videogame_impl.data.indexToPlayer
import io.paritytech.polkadotapp.feature_videogame_impl.data.mappers.toDomain
import io.paritytech.polkadotapp.feature_videogame_impl.data.mappers.toLocal
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.AccountOrPersonData
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.FullVideoGameReport
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.*
import io.paritytech.polkadotapp.feature_videogame_impl.data.nftCandidates
import io.paritytech.polkadotapp.feature_videogame_impl.data.nfts
import io.paritytech.polkadotapp.feature_videogame_impl.data.offboard
import io.paritytech.polkadotapp.feature_videogame_impl.data.origins.ScoreOrigins
import io.paritytech.polkadotapp.feature_videogame_impl.data.pendingInvites
import io.paritytech.polkadotapp.feature_videogame_impl.data.phaseDurations
import io.paritytech.polkadotapp.feature_videogame_impl.data.playerToIndex
import io.paritytech.polkadotapp.feature_videogame_impl.data.players
import io.paritytech.polkadotapp.feature_videogame_impl.data.report
import io.paritytech.polkadotapp.feature_videogame_impl.data.schedule
import io.paritytech.polkadotapp.feature_videogame_impl.data.signUpWithAccount
import io.paritytech.polkadotapp.feature_videogame_impl.data.signUpWithAlias
import io.paritytech.polkadotapp.feature_videogame_impl.data.signUpWithInvitation
import io.paritytech.polkadotapp.feature_videogame_impl.data.storedPhaseDurationsOrNull
import io.paritytech.polkadotapp.feature_videogame_impl.data.videoGame
import io.paritytech.polkadotapp.feature_videogame_impl.domain.airdrop.AirdropProof
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameVote
import io.paritytech.polkadotapp.feature_videogame_impl.domain.tracked.VideoGameExtrinsicTags
import io.paritytech.polkadotapp.feature_videogame_impl.domain.tracked.VideoGamePlayerOverrideTarget
import io.paritytech.polkadotapp.feature_videogame_impl.domain.tracked.VideoGameTrackedSubmission
import io.paritytech.polkadotapp.feature_videogame_impl.domain.tracked.encodeToAdditional
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import timber.log.Timber
import javax.inject.Inject

interface VideoGameRepositoryInternal {
    context(scope: ComputationalScope)
    fun subscribeGameInfoAtBlock(chainId: ChainId): Flow<AtBlock<OnChainVideoGameInfo?>>

    fun subscribePlayer(
        chainId: ChainId,
        player: OnChainAccountOrPerson
    ): Flow<OnChainVideoGamePlayerInfo?>

    suspend fun getPlayer(
        chainId: ChainId,
        player: OnChainAccountOrPerson
    ): Result<OnChainVideoGamePlayerInfo?>

    fun subscribeArchivedPlayer(
        chainId: ChainId,
        player: OnChainAccountOrPerson
    ): Flow<OnChainArchivedPlayer?>

    context(scope: ComputationalScope)
    fun subscribeGamesSchedule(chainId: ChainId): Flow<List<OnChainVideoGameSchedule>>

    suspend fun getPlayersByIndexes(
        chainId: ChainId,
        at: BlockHash?,
        keys: List<OnChainVideoGamePlayerRoundKey>
    ): Result<Map<OnChainVideoGamePlayerRoundKey, OnChainAccountOrPerson>>

    suspend fun resolvePlayerAccountIds(
        chainId: ChainId,
        keys: Collection<OnChainAccountOrPerson>
    ): Result<Map<OnChainAccountOrPerson, AccountId>>

    suspend fun getPlayerIndexes(
        chainId: ChainId,
        at: BlockHash?,
        player: OnChainAccountOrPerson
    ): Result<List<Int>>

    suspend fun getMintedNftHashes(
        chainId: ChainId,
        at: BlockHash?,
        owner: OnChainAccountOrPerson,
        candidateHashes: List<AttestationNftHash>
    ): Result<Set<AttestationNftHash>>

    suspend fun getPendingNftHashes(
        chainId: ChainId,
        at: BlockHash?,
        owner: OnChainAccountOrPerson
    ): Result<List<AttestationNftHash>>

    fun subscribeMintedNfts(
        chainId: ChainId,
        owner: OnChainAccountOrPerson,
        candidateHashes: List<AttestationNftHash>
    ): Flow<Set<AttestationNftHash>>

    suspend fun saveVotes(votes: List<VideoGameVote>)
    suspend fun getSavedVotesForGame(gameIndex: GameIndex): List<VideoGameVote>
    suspend fun clearVotes()

    suspend fun registerViaInvitation(
        issuedInvitation: IssuedInvitation,
        chain: Chain,
        publicKey: AccountEcdhKey,
        submission: VideoGameTrackedSubmission,
        airdrop: AirdropProof?,
    ): Result<Unit>

    suspend fun registerWithAccount(
        chain: Chain,
        needCredibilityProof: Boolean,
        publicKey: AccountEcdhKey,
        submission: VideoGameTrackedSubmission,
        airdrop: AirdropProof?,
    ): Result<Unit>

    suspend fun registerWithAlias(
        chain: Chain,
        statementAccountId: AccountId,
        statementAccountSignature: MultiSignature,
        submission: VideoGameTrackedSubmission,
        airdrop: AirdropProof?,
    ): Result<Unit>

    suspend fun generateStatementAccountSigningMessage(alias: PersonalAlias): ByteArray

    suspend fun submitReportAsAccount(chain: Chain, report: FullVideoGameReport, submission: VideoGameTrackedSubmission): Result<Unit>

    suspend fun submitReportAsPerson(chain: Chain, report: FullVideoGameReport, submission: VideoGameTrackedSubmission): Result<Unit>

    /**
     * Claims the airdrop prize for [gameIndex], paying [beneficiary]. Signed with the same identity
     * that registered — alias origin when [recognized], account origin otherwise — so the signer
     * matches the on-chain registration entry.
     */
    suspend fun claimAirdrop(chain: Chain, gameIndex: GameIndex, beneficiary: AccountId, recognized: Boolean): Result<Unit>

    suspend fun getRegistrationRequiredAmount(chain: Chain, asset: Chain.Asset): Balance

    suspend fun getGamePhaseDurations(chainId: ChainId): Result<OnChainVideoGamePhaseDurations>

    suspend fun offboard(chain: Chain): Result<Unit>

    suspend fun getCommunicationIdentifier(
        chainId: ChainId,
        accountId: AccountId
    ): Result<AccountEcdhKey?>
}

context(scope: ComputationalScope)
fun VideoGameRepositoryInternal.subscribeGameInfo(chainId: ChainId): Flow<OnChainVideoGameInfo?> {
    return subscribeGameInfoAtBlock(chainId).map { it.value }
}

fun VideoGameRepositoryInternal.subscribeOurPlayer(
    chainId: ChainId,
    ourAccountId: AccountId,
    ourScoreAlias: PersonalAlias
): Flow<AccountOrPersonData<OnChainVideoGamePlayerInfo>?> {
    return combine(
        subscribeAccountPlayer(chainId, ourAccountId),
        subscribePersonPlayer(chainId, ourScoreAlias),
    ) { accountPlayer, personPlayer ->
        when {
            accountPlayer != null -> AccountOrPersonData.fromAccount(accountPlayer, ourAccountId)
            personPlayer != null -> AccountOrPersonData.fromPerson(personPlayer, ourScoreAlias)
            else -> null
        }
    }
}

fun VideoGameRepositoryInternal.subscribeAccountPlayer(
    chainId: ChainId,
    accountId: AccountId,
): Flow<OnChainVideoGamePlayerInfo?> {
    return subscribePlayer(chainId, OnChainAccountOrPerson.Account(accountId))
}

fun VideoGameRepositoryInternal.subscribePersonPlayer(
    chainId: ChainId,
    ourScoreAlias: PersonalAlias
): Flow<OnChainVideoGamePlayerInfo?> {
    return subscribePlayer(chainId, OnChainAccountOrPerson.Person(ourScoreAlias))
}

fun VideoGameRepositoryInternal.subscribeAccountArchivedPlayer(
    chainId: ChainId,
    accountId: AccountId,
): Flow<OnChainArchivedPlayer?> {
    return subscribeArchivedPlayer(chainId, OnChainAccountOrPerson.Account(accountId))
}

class RealVideoGameRepository @Inject constructor(
    @param:RemoteSourceQualifier private val remoteStorageDataSource: StorageDataSource,
    @param:LocalSourceQualifier private val localStorageDataSource: StorageDataSource,
    private val extrinsicService: ExtrinsicService,
    private val trackedExtrinsicService: TrackedExtrinsicService,
    private val chainRegistry: ChainRegistry,
    private val videoGameVoteDao: VideoGameVoteDao,
    private val multiChainRuntimeCallsApi: MultiChainRuntimeCallsApi,
    private val tokenTypeRegistry: TokenBalanceTypeRegistry,
    private val scoreOrigins: ScoreOrigins,
    private val peopleOrigins: PeopleOrigins,
    private val computationalCache: ComputationalCache,
    private val signedOrigins: SignedOrigins,
    private val scoreContextProvider: ScoreContextProvider,
) : VideoGameRepositoryInternal, VideoGameRepository {
    context(scope: ComputationalScope)
    override fun subscribeGameInfoAtBlock(chainId: ChainId): Flow<AtBlock<OnChainVideoGameInfo?>> {
        return computationalCache.useSharedFlow("GameInfoAtBlock", chainId) {
            remoteStorageDataSource.subscribe(chainId) {
                metadata.videoGame.game.observeWithRaw().map { it.toAtBlock() }
                    .catch {
                        Timber.e(it, "Failed to subscribe to game info")
                    }
            }
        }
    }

    override fun subscribePlayer(
        chainId: ChainId,
        player: OnChainAccountOrPerson
    ): Flow<OnChainVideoGamePlayerInfo?> {
        return localStorageDataSource.subscribe(chainId) {
            metadata.videoGame.players.observe(player)
        }
    }

    override suspend fun getPlayer(
        chainId: ChainId,
        player: OnChainAccountOrPerson
    ): Result<OnChainVideoGamePlayerInfo?> {
        return remoteStorageDataSource.queryCatching(chainId, at = null) {
            metadata.videoGame.players.query(player)
        }
    }

    override fun subscribeArchivedPlayer(
        chainId: ChainId,
        player: OnChainAccountOrPerson
    ): Flow<OnChainArchivedPlayer?> {
        return localStorageDataSource.subscribe(chainId) {
            metadata.videoGame.archivedPlayers.observe(player)
        }
    }

    context(scope: ComputationalScope)
    override fun subscribeGamesSchedule(chainId: ChainId): Flow<List<OnChainVideoGameSchedule>> {
        return computationalCache.useSharedFlow("GamesSchedule", chainId) {
            remoteStorageDataSource.subscribe(chainId) {
                metadata.videoGame.schedule.observe().map { it.orEmpty() }
            }
        }
    }

    override suspend fun getPlayersByIndexes(
        chainId: ChainId,
        at: BlockHash?,
        keys: List<OnChainVideoGamePlayerRoundKey>
    ): Result<Map<OnChainVideoGamePlayerRoundKey, OnChainAccountOrPerson>> {
        return remoteStorageDataSource.queryCatching(chainId, at) {
            metadata.videoGame.indexToPlayer.entries(keys)
        }
    }

    override suspend fun resolvePlayerAccountIds(
        chainId: ChainId,
        keys: Collection<OnChainAccountOrPerson>
    ): Result<Map<OnChainAccountOrPerson, AccountId>> {
        return runCancellableCatching {
            val accounts = keys.filterIsInstance<OnChainAccountOrPerson.Account>()
            val persons = keys.filterIsInstance<OnChainAccountOrPerson.Person>()

            resolveAccountPlayerAccountIds(accounts) +
                resolvePersonPlayerAccountIds(chainId, persons)
        }
    }

    override suspend fun getPlayerIndexes(
        chainId: ChainId,
        at: BlockHash?,
        player: OnChainAccountOrPerson
    ): Result<List<Int>> {
        return remoteStorageDataSource.queryCatching(chainId, at) {
            metadata.videoGame.playerToIndex.query(player).orEmpty()
        }
    }

    override suspend fun getMintedNftHashes(
        chainId: ChainId,
        at: BlockHash?,
        owner: OnChainAccountOrPerson,
        candidateHashes: List<AttestationNftHash>
    ): Result<Set<AttestationNftHash>> {
        if (candidateHashes.isEmpty()) return Result.success(emptySet())

        return remoteStorageDataSource.queryCatching(chainId, at) {
            metadata.videoGame.nfts
                .findExistingKeys(candidateHashes.map { hash -> owner to hash })
                .mapToSet { (_, hash) -> hash }
        }
    }

    override suspend fun getPendingNftHashes(
        chainId: ChainId,
        at: BlockHash?,
        owner: OnChainAccountOrPerson
    ): Result<List<AttestationNftHash>> {
        return remoteStorageDataSource.queryCatching(chainId, at) {
            metadata.videoGame.nftCandidates.keys(owner).map { (_, hash) -> hash.toDataByteArray() }
        }
    }

    override fun subscribeMintedNfts(
        chainId: ChainId,
        owner: OnChainAccountOrPerson,
        candidateHashes: List<AttestationNftHash>
    ): Flow<Set<AttestationNftHash>> {
        if (candidateHashes.isEmpty()) return flowOf(emptySet())

        return remoteStorageDataSource.subscribe(chainId) {
            metadata.videoGame.nfts.observe(candidateHashes.map { hash -> owner to hash })
        }.map { byKey ->
            byKey.entries
                .filter { (_, mintedAt) -> mintedAt != null }
                .mapToSet { (key, _) -> key.second }
        }.catch { Timber.w(it, "Failed to subscribe to minted NFTs") }
    }

    override suspend fun saveVotes(votes: List<VideoGameVote>) {
        videoGameVoteDao.insertVotes(votes.map { it.toLocal() })
    }

    override suspend fun getSavedVotesForGame(gameIndex: GameIndex): List<VideoGameVote> {
        return videoGameVoteDao.getVotesForGame(gameIndex.value).map { it.toDomain() }
    }

    override suspend fun clearVotes() {
        videoGameVoteDao.removeAllVotes()
    }

    override suspend fun registerViaInvitation(
        issuedInvitation: IssuedInvitation,
        chain: Chain,
        publicKey: AccountEcdhKey,
        submission: VideoGameTrackedSubmission,
        airdrop: AirdropProof?,
    ): Result<Unit> {
        return submitTracked(chain, signedOrigins.candidate(), submission) {
            videoGame.signUpWithInvitation(
                identifierKey = publicKey.toScale().encodeOnChain(),
                inviter = issuedInvitation.inviter,
                ticket = issuedInvitation.ticket,
                signature = issuedInvitation.signature,
                airdrop = airdrop?.toAirdropVrf(),
            )
        }
    }

    override suspend fun registerWithAccount(
        chain: Chain,
        needCredibilityProof: Boolean,
        publicKey: AccountEcdhKey,
        submission: VideoGameTrackedSubmission,
        airdrop: AirdropProof?,
    ): Result<Unit> {
        val origin = registerWithAccountOrigin(needCredibilityProof)

        return submitTracked(chain, origin, submission) {
            videoGame.signUpWithAccount(publicKey.toScale().encodeOnChain(), airdrop = airdrop?.toAirdropVrf())
        }
    }

    override suspend fun registerWithAlias(
        chain: Chain,
        statementAccountId: AccountId,
        statementAccountSignature: MultiSignature,
        submission: VideoGameTrackedSubmission,
        airdrop: AirdropProof?,
    ): Result<Unit> {
        return peopleOrigins.asPersonalAliasWithAccountEnsuringRevision(
            scoreContextProvider.context()
        ).flatMap { origin ->
            submitTracked(chain, origin, submission) {
                videoGame.signUpWithAlias(statementAccountId, statementAccountSignature, airdrop = airdrop?.toAirdropVrf())
            }
        }
    }

    override suspend fun generateStatementAccountSigningMessage(alias: PersonalAlias): ByteArray {
        val prefix = "pop:game:stmt_account_for_alias:".encodeToByteArray()
        return (prefix + alias.value).blake2b256()
    }

    override suspend fun claimAirdrop(
        chain: Chain,
        gameIndex: GameIndex,
        beneficiary: AccountId,
        recognized: Boolean,
    ): Result<Unit> {
        val origin = if (recognized) {
            peopleOrigins.asPersonalAliasWithAccountEnsuringRevision(scoreContextProvider.context())
        } else {
            Result.success(scoreOrigins.asAccountParticipant())
        }
        return origin.flatMap { txOrigin ->
            trackedExtrinsicService.submit(
                tag = VideoGameExtrinsicTags.claim(gameIndex),
                chain = chain,
                origin = txOrigin,
                additional = null,
            ) {
                videoGame.claimAirdrop(gameIndex.value, beneficiary)
            }
        }
    }

    private fun resolveAccountPlayerAccountIds(
        keys: Collection<OnChainAccountOrPerson.Account>
    ): Map<OnChainAccountOrPerson.Account, AccountId> {
        return keys.associateWith { it.accountId }
    }

    private suspend fun resolvePersonPlayerAccountIds(
        chainId: ChainId,
        keys: Collection<OnChainAccountOrPerson.Person>
    ): Map<OnChainAccountOrPerson.Person, AccountId> {
        if (keys.isEmpty()) return emptyMap()

        val aliases = keys.map { it.alias }

        return remoteStorageDataSource.query(chainId) {
            metadata.videoGame.aliasToStmtAccount.entries(aliases)
        }
            .mapKeys { (alias, _) -> OnChainAccountOrPerson.Person(alias) }
    }

    private suspend fun registerWithAccountOrigin(isFirstGame: Boolean): TransactionOrigin {
        return if (isFirstGame) {
            signedOrigins.candidate()
        } else {
            scoreOrigins.asAccountParticipant()
        }
    }

    override suspend fun submitReportAsAccount(
        chain: Chain,
        report: FullVideoGameReport,
        submission: VideoGameTrackedSubmission,
    ): Result<Unit> {
        return submitTracked(chain, scoreOrigins.asAccountParticipant(), submission) {
            videoGame.report(report)
        }
    }

    override suspend fun submitReportAsPerson(
        chain: Chain,
        report: FullVideoGameReport,
        submission: VideoGameTrackedSubmission,
    ): Result<Unit> {
        return peopleOrigins.asPersonalAliasWithAccountEnsuringRevision(scoreContextProvider.context()).flatMap { origin ->
            submitTracked(chain, origin, submission) {
                videoGame.report(report)
            }
        }
    }

    // Submits as a tracked extrinsic, recording the player override target in `additional`. Returns as soon as
    // the tx is built, pre-validated and enqueued — it does NOT wait for the node to accept it. The worker drives
    // it to a terminal status off-screen, and the storage override already reflects the in-flight tx in chain
    // reads, so the caller can proceed immediately. submit() rejects a definitely-invalid tx synchronously.
    private suspend fun submitTracked(
        chain: Chain,
        origin: TransactionOrigin,
        submission: VideoGameTrackedSubmission,
        formExtrinsic: FormExtrinsic,
    ): Result<Unit> {
        val additional = buildOverrideAdditional(chain.id, submission)

        return trackedExtrinsicService.submit(
            tag = submission.tag,
            chain = chain,
            origin = origin,
            additional = additional,
            formExtrinsic = formExtrinsic,
        )
    }

    private suspend fun buildOverrideAdditional(chainId: ChainId, submission: VideoGameTrackedSubmission): DataByteArray {
        val storageKey = chainRegistry.withRuntime(chainId) {
            runtime.metadata.videoGame.players.storageKey(submission.player)
        }

        return VideoGamePlayerOverrideTarget(storageKey, submission.gameIndex).encodeToAdditional()
    }

    override suspend fun getRegistrationRequiredAmount(chain: Chain, asset: Chain.Asset): Balance {
        val registrationDeposit = getRegistrationDeposit(chain, asset)

        val applyFee = extrinsicService.estimateFee(
            chain = chain,
            options = ExtrinsicService.SubmissionOptions(
                mortality = Mortality.immortal(chain)
            ),
            origin = signedOrigins.candidate()
        ) {
            // Fee estimation omits the airdrop proof: sign-up is Pays::No and the required-balance
            // calc has a 2× fee buffer, so the proof's length doesn't affect it.
            videoGame.signUpWithAccount(ByteArray(65) { 1 }, airdrop = null)
        }
            .map { it.amount }
            .logFailure("Failed to calculate fee for game registration deposit")
            .getOrDefault(Balance.ZERO)

        val minimumBalance = tokenTypeRegistry.typeFor(asset).minimumBalance()

        return registrationDeposit.amount + minimumBalance + applyFee
    }

    override suspend fun getGamePhaseDurations(chainId: ChainId): Result<OnChainVideoGamePhaseDurations> {
        return remoteStorageDataSource.queryCatching(chainId) {
            metadata.videoGame.storedPhaseDurationsOrNull?.query()
                ?: metadata.videoGame.phaseDurations
        }
    }

    override suspend fun offboard(chain: Chain): Result<Unit> {
        return extrinsicService.submitExtrinsicAndAwaitExecution(
            chain = chain,
            origin = scoreOrigins.asAccountParticipant()
        ) {
            videoGame.offboard()
        }
            .flattenExecutionFailure()
            .coerceToUnit()
    }

    override fun subscribePendingInvites(
        chainId: ChainId,
        inviter: AccountId,
        ticket: EncodedPublicKey
    ): Flow<Boolean> {
        return remoteStorageDataSource.subscribe(chainId) {
            metadata.videoGame.pendingInvites.observe(inviter, ticket)
        }.map { it === Unit }
    }

    private suspend fun RuntimeCallsApi.registrationDeposit(): Balance {
        return call(
            section = "PalletGameApi",
            method = "play_deposit",
            arguments = emptyMap(),
            returnBinding = ::bindBalance
        )
    }

    override suspend fun getCommunicationIdentifier(
        chainId: ChainId,
        accountId: AccountId
    ): Result<AccountEcdhKey?> {
        return remoteStorageDataSource.queryCatching(chainId, at = null) {
            metadata.videoGame.communicationIdentifiers.query(accountId)
        }.mapCatching { it?.toDomain()?.getOrThrow() }
    }

    private suspend fun getRegistrationDeposit(chain: Chain, asset: Chain.Asset): ChainAssetWithAmount {
        val runtimeApi = multiChainRuntimeCallsApi.forChain(chain.id)
        val registrationDeposit = runtimeApi.registrationDeposit()
        val assetWithAmount = asset.withAmount(registrationDeposit)
        return assetWithAmount
    }
}
