package io.paritytech.polkadotapp.feature_videogame_impl.domain.interactor

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainAssetWithAmount
import io.paritytech.polkadotapp.chains.util.planksFromAmount
import io.paritytech.polkadotapp.chains.util.signing.MessageSigningContext
import io.paritytech.polkadotapp.common.BuildConfig
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.data.network.TestnetEnvironment
import io.paritytech.polkadotapp.common.domain.model.AccountEcdhKey
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.runCancellableCatching
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_account_api.data.repository.getWalletAccountIdIn
import io.paritytech.polkadotapp.feature_account_api.data.sign.AccountBytesSigner
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.BandersnatchSecretsStorage
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.getAliasInContext
import io.paritytech.polkadotapp.feature_account_api.domain.model.SharedSecretDerivationDomain
import io.paritytech.polkadotapp.feature_account_api.domain.usecase.SharedSecretDerivationUseCase
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.CandidateDepositAssetProvider
import io.paritytech.polkadotapp.feature_people_api.domain.dim.DimState
import io.paritytech.polkadotapp.feature_people_api.domain.dim.GetActiveDimCommitmentState
import io.paritytech.polkadotapp.feature_people_api.domain.invitation.DimName
import io.paritytech.polkadotapp.feature_people_api.domain.invitation.InvitationService
import io.paritytech.polkadotapp.feature_people_api.domain.invitation.IssueInvitationResult
import io.paritytech.polkadotapp.feature_people_api.domain.invitation.IssuedInvitation
import io.paritytech.polkadotapp.feature_tokens_api.domain.ChainAssetProvider
import io.paritytech.polkadotapp.feature_transfers_api.domain.usecase.TestnetFundUseCase
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.model.UpgradeToFullUsernameState
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.usecase.ReadyToUpgradeUsernameUseCase
import io.paritytech.polkadotapp.feature_usernames_api.domain.usecase.UsernameOfAccountUseCase
import io.paritytech.polkadotapp.feature_videogame_api.domain.models.UpcomingGameStart
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.VideoGamesProgressUseCase
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.VideoGamesProgress
import io.paritytech.polkadotapp.feature_videogame_api.domain.usecase.UpcomingGameStartUseCase
import io.paritytech.polkadotapp.feature_videogame_impl.data.ScoreContextProvider
import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameInfoSyncService
import io.paritytech.polkadotapp.feature_videogame_impl.data.getCurrentActiveGameInfo
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameRegistrationStage
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.isRecognized
import io.paritytech.polkadotapp.feature_videogame_impl.data.notifications.VideoGameSettingsPreferences
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.ScoreRepository
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameRepositoryInternal
import io.paritytech.polkadotapp.feature_videogame_impl.domain.airdrop.AirdropProof
import io.paritytech.polkadotapp.feature_videogame_impl.domain.airdrop.AirdropProofFactory
import io.paritytech.polkadotapp.feature_videogame_impl.domain.airdrop.AirdropRegistrationGate
import io.paritytech.polkadotapp.feature_videogame_impl.domain.dim.Dim2CommitmentHandler
import io.paritytech.polkadotapp.feature_videogame_impl.domain.invitation.Game
import io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications.GameStartAlarmOffset
import io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications.VideoGameReminderScheduler
import io.paritytech.polkadotapp.feature_videogame_impl.domain.telemetry.GameDashboardTelemetryEmitter
import io.paritytech.polkadotapp.feature_videogame_impl.domain.tracked.VideoGameExtrinsicTags
import io.paritytech.polkadotapp.feature_videogame_impl.domain.tracked.VideoGamePlayerKeyResolver
import io.paritytech.polkadotapp.feature_videogame_impl.domain.tracked.VideoGameTrackedSubmission
import io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase.VideoGameRegistrationStageUseCase
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.models.WeeklyGameFooterState
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

internal interface VideoGameChatBotFooterInteractor {
    context(scope: ComputationalScope)
    suspend fun register(): Result<RegisterOutcome>

    context(scope: ComputationalScope)
    fun subscribeUpcomingGame(): Flow<UpcomingGameStart?>

    context(scope: ComputationalScope)
    fun subscribeIsMember(): Flow<Boolean>

    context(scope: ComputationalScope)
    fun subscribeRegistrationStage(): Flow<VideoGameRegistrationStage>

    context(scope: ComputationalScope)
    fun subscribeAirdropRegistrationReady(): Flow<Boolean>

    context(scope: ComputationalScope)
    fun subscribeFooterState(): Flow<WeeklyGameFooterState>

    context(scope: ComputationalScope)
    suspend fun deposit(): Result<Unit>

    fun subscribeReadyToUpgradeUsername(): Flow<UpgradeToFullUsernameState>

    fun getAlarmOffset(): GameStartAlarmOffset

    fun setAlarmOffset(offset: GameStartAlarmOffset)

    context(scope: ComputationalScope)
    suspend fun rescheduleGameStartAlarm()
}

internal class RealVideoGameChatBotFooterInteractor @Inject constructor(
    private val upcomingGameStartUseCase: UpcomingGameStartUseCase,
    private val videoGameRegistrationStageUseCase: VideoGameRegistrationStageUseCase,
    private val gamesProgressUseCase: VideoGamesProgressUseCase,
    private val testnetFundUseCase: TestnetFundUseCase,
    @CandidateDepositAssetProvider private val chainAssetProvider: ChainAssetProvider,
    private val environment: TestnetEnvironment,
    private val accountRepository: AccountRepository,
    private val readyToUpgradeUsernameUseCase: ReadyToUpgradeUsernameUseCase,
    private val videoGameRepository: VideoGameRepositoryInternal,
    private val candidateBytesSigner: AccountBytesSigner,
    private val chainRegistry: ChainRegistry,
    private val sharedSecretDerivationUseCase: SharedSecretDerivationUseCase,
    private val bandersnatchSecretsStorage: BandersnatchSecretsStorage,
    private val getActiveDimCommitmentState: GetActiveDimCommitmentState,
    private val alarmPreferences: VideoGameSettingsPreferences,
    private val videoGameReminderScheduler: VideoGameReminderScheduler,
    private val gameInfoSyncService: VideoGameInfoSyncService,
    private val invitationService: InvitationService,
    private val gameDashboardTelemetry: GameDashboardTelemetryEmitter,
    private val usernameOfAccountUseCase: UsernameOfAccountUseCase,
    private val playerKeyResolver: VideoGamePlayerKeyResolver,
    private val airdropProofFactory: AirdropProofFactory,
    private val airdropRegistrationGate: AirdropRegistrationGate,
    private val scoreRepository: ScoreRepository,
    private val scoreContextProvider: ScoreContextProvider,
) : VideoGameChatBotFooterInteractor {
    companion object {
        private val TESTNET_TOP_UP_AMOUNT = 10.toBigDecimal()
        private val NIGHTLY_TOP_UP_AMOUNT = 10.toBigDecimal()
    }

    context(scope: ComputationalScope)
    override suspend fun register(): Result<RegisterOutcome> = runCancellableCatching {
        videoGameRepository.clearVotes()

        val outcome = when (val stage = videoGameRegistrationStageUseCase.get()) {
            VideoGameRegistrationStage.Registered -> RegisterOutcome.Submitted

            is VideoGameRegistrationStage.CanRegister.NoCredibilityProofRequired -> {
                registerNoCredibilityProof(stage.externallyRecognized).onFailure { throw it }
                RegisterOutcome.Submitted
            }

            is VideoGameRegistrationStage.CanRegister.WithCredibilityProof -> {
                val cached = stage.cachedInvite
                if (cached != null) registerWithCachedInvite(cached, stage.requiredDeposit)
                else registerIssuingNewInvite(stage.requiredDeposit)
            }

            is VideoGameRegistrationStage.NeedsCredibilityProof ->
                registerIssuingNewInvite(stage.requiredDeposit)
        }

        if (outcome is RegisterOutcome.Submitted) {
            scope.launch { emitRegistrationTelemetry() }
        }

        outcome
    }

    context(scope: ComputationalScope)
    private suspend fun registerSubmission(externallyRecognized: Boolean): VideoGameTrackedSubmission {
        val gameIndex = gameInfoSyncService.getCurrentActiveGameInfo().index
        return VideoGameTrackedSubmission(
            tag = VideoGameExtrinsicTags.register(gameIndex),
            player = playerKeyResolver.resolve(externallyRecognized),
            gameIndex = gameIndex,
        )
    }

    private suspend fun emitRegistrationTelemetry() {
        val chain = chainRegistry.peopleChain()
        val candidate = accountRepository.getCandidateAccount()
        val accountId = candidate.accountIdIn(chain)
        val storedUsername = usernameOfAccountUseCase.getUsername().getOrNull()
        if (storedUsername == null) {
            Timber.w("Skipping dashboard registration telemetry — username unexpectedly nil")
            return
        }
        val usernameAccountId = accountRepository.getWalletAccountIdIn(chain)

        gameDashboardTelemetry.submitRegistration(
            localAccount = accountId,
            usernameAccountId = usernameAccountId,
            username = storedUsername.username.getDisplayUsername()
        )
    }

    context(scope: ComputationalScope)
    private suspend fun registerNoCredibilityProof(externallyRecognized: Boolean): Result<Unit> {
        val chain = chainRegistry.peopleChain()
        return if (externallyRecognized) {
            registerWithAlias(chain)
        } else {
            registerWithAccount(chain = chain, needsCredibilityProof = false)
        }
    }

    context(scope: ComputationalScope)
    private suspend fun registerWithCachedInvite(
        cachedInvite: IssuedInvitation,
        requiredDeposit: ChainAssetWithAmount,
    ): RegisterOutcome {
        val chain = chainRegistry.peopleChain()
        val airdrop = resolveAirdropProof(externallyRecognized = false).getOrElse { throw it }
        val cachedResult = videoGameRepository.registerViaInvitation(
            cachedInvite,
            chain,
            deriveCandidatePublicKey(),
            registerSubmission(externallyRecognized = false),
            airdrop = airdrop,
        )

        if (cachedResult.isSuccess) return RegisterOutcome.Submitted

        Timber.w(cachedResult.exceptionOrNull(), "Cached invite registration failed; trying on-the-fly")
        return registerIssuingNewInvite(requiredDeposit)
    }

    context(scope: ComputationalScope)
    private suspend fun registerIssuingNewInvite(
        requiredDeposit: ChainAssetWithAmount,
    ): RegisterOutcome {
        val chain = chainRegistry.peopleChain()
        val candidate = accountRepository.getCandidateAccount()
        // Resolved once and reused across the invitation retry path.
        val airdrop = resolveAirdropProof(externallyRecognized = false).getOrElse { throw it }

        return when (val issuance = invitationService.issueInvitation(chain, candidate, DimName.Game)) {
            is IssueInvitationResult.Success -> {
                val claimResult = issuance.consumable.tryConsume { invite ->
                    videoGameRepository.registerViaInvitation(
                        invite,
                        chain,
                        deriveCandidatePublicKey(),
                        registerSubmission(externallyRecognized = false),
                        airdrop = airdrop,
                    )
                }
                if (claimResult.isSuccess) {
                    RegisterOutcome.Submitted
                } else {
                    Timber.w(claimResult.exceptionOrNull(), "On-the-fly invitation claim failed; falling back to deposit")
                    RegisterOutcome.NeedsDeposit(requiredDeposit)
                }
            }
            IssueInvitationResult.AlreadyUsed,
            IssueInvitationResult.Unavailable,
            IssueInvitationResult.BackendUnavailable -> RegisterOutcome.NeedsDeposit(requiredDeposit)
            is IssueInvitationResult.Failed -> {
                Timber.w(issuance.error, "On-the-fly invitation failed; falling back to deposit")
                RegisterOutcome.NeedsDeposit(requiredDeposit)
            }
        }
    }

    context(scope: ComputationalScope)
    private suspend fun registerWithAccount(chain: Chain, needsCredibilityProof: Boolean): Result<Unit> {
        val keypair = sharedSecretDerivationUseCase.deriveForDomain(SharedSecretDerivationDomain.CANDIDATE)
        val publicKey = AccountEcdhKey.X25519(keypair.publicKey)

        return resolveAirdropProof(externallyRecognized = false).flatMap { airdrop ->
            videoGameRepository.registerWithAccount(
                chain = chain,
                needCredibilityProof = needsCredibilityProof,
                publicKey = publicKey,
                submission = registerSubmission(externallyRecognized = false),
                airdrop = airdrop,
            )
        }
    }

    private suspend fun deriveCandidatePublicKey(): AccountEcdhKey {
        val keypair = sharedSecretDerivationUseCase.deriveForDomain(SharedSecretDerivationDomain.CANDIDATE)
        return AccountEcdhKey.X25519(keypair.publicKey)
    }

    context(scope: ComputationalScope)
    private suspend fun registerWithAlias(chain: Chain): Result<Unit> {
        val candidateAccount = accountRepository.getCandidateAccount()
        val alias = bandersnatchSecretsStorage.getAliasInContext(candidateAccount.id, scoreContextProvider.context())
        val aliasAccount = accountRepository.getAliasAccount(scoreContextProvider.context())

        val message = videoGameRepository.generateStatementAccountSigningMessage(alias)

        val signature = candidateBytesSigner.signRawBytes(message, MessageSigningContext.trustedContent(), aliasAccount)
        val aliasAccountId = aliasAccount.accountIdIn(chain)

        return resolveAirdropProof(externallyRecognized = true).flatMap { airdrop ->
            videoGameRepository.registerWithAlias(
                chain,
                aliasAccountId,
                signature,
                registerSubmission(externallyRecognized = true),
                airdrop = airdrop,
            )
        }
    }

    // Resolves the airdrop lottery proof for an airdrop-scheduled game. A build failure is fatal to
    // registration (propagated, not swallowed): registering without it would forfeit the ticket.
    context(scope: ComputationalScope)
    private suspend fun resolveAirdropProof(externallyRecognized: Boolean): Result<AirdropProof?> {
        val gameInfo = gameInfoSyncService.getCurrentActiveGameInfo()
        if (!gameInfo.airdropScheduled) {
            return Result.success(null)
        }
        val chainId = chainRegistry.peopleChain().id
        val playerKey = playerKeyResolver.resolve(externallyRecognized)

        // The runtime picks the required proof variant from the player's ON-CHAIN recognition
        // (`Recognition::is_recognized`), which can flip right after a game — so read it fresh
        // from the chain rather than trusting local game progress.
        return scoreRepository.getParticipantFresh(chainId, playerKey).flatMap { participant ->
            val recognized = participant?.recognition?.isRecognized() == true
            airdropProofFactory.makeProof(
                chainId = chainId,
                gameIndex = gameInfo.index,
                playerKey = playerKey,
                recognized = recognized,
            )
        }.recover { error ->
            Timber.w(error, "[Airdrop] register: proof build FAILED — registering WITHOUT airdrop (best-effort)")
            null
        }
    }

    context(scope: ComputationalScope)
    override fun subscribeUpcomingGame(): Flow<UpcomingGameStart?> =
        upcomingGameStartUseCase.subscribe()

    context(scope: ComputationalScope)
    override fun subscribeIsMember(): Flow<Boolean> =
        gamesProgressUseCase.videoGamesProgressFlow().map { it.isMember() }

    private fun VideoGamesProgress.isMember(): Boolean = when (this) {
        is VideoGamesProgress.PersonhoodReached,
        VideoGamesProgress.ExternallyRecognized,
        is VideoGamesProgress.ReadyToReachPersonhood,
        is VideoGamesProgress.FinalGameProcessing -> true
        is VideoGamesProgress.NotStarted,
        is VideoGamesProgress.PlayingGames -> false
    }

    context(scope: ComputationalScope)
    override fun subscribeRegistrationStage(): Flow<VideoGameRegistrationStage> =
        videoGameRegistrationStageUseCase.subscribe()

    context(scope: ComputationalScope)
    override fun subscribeAirdropRegistrationReady(): Flow<Boolean> =
        airdropRegistrationGate.subscribe()

    context(scope: ComputationalScope)
    override fun subscribeFooterState(): Flow<WeeklyGameFooterState> =
        getActiveDimCommitmentState(Dim2CommitmentHandler.DIM_ID)
            .map { state ->
                when (state) {
                    is DimState.Started -> {
                        if (BuildConfig.DIM1_ENABLED) WeeklyGameFooterState.OtherDimCommitted
                        else WeeklyGameFooterState.Normal
                    }
                    DimState.NotStarted, null -> WeeklyGameFooterState.Normal
                }
            }

    context(scope: ComputationalScope)
    override suspend fun deposit(): Result<Unit> {
        val chainAsset = chainAssetProvider()
        val amount = when (environment) {
            TestnetEnvironment.TESTNET -> TESTNET_TOP_UP_AMOUNT
            TestnetEnvironment.NIGHTLY, TestnetEnvironment.PRODUCTION -> NIGHTLY_TOP_UP_AMOUNT
        }
        val topUpAmount = amount.planksFromAmount(chainAsset.asset.precision)
        val recipientAccountId = accountRepository.getCandidateAccount().accountIdIn(chainAsset.chain)
        return testnetFundUseCase(chainAsset, topUpAmount, recipientAccountId)
            .fold(
                onSuccess = { registerWithAccount(chain = chainAsset.chain, needsCredibilityProof = true) },
                onFailure = { Result.failure(it) },
            )
    }

    override fun subscribeReadyToUpgradeUsername() = readyToUpgradeUsernameUseCase()

    override fun getAlarmOffset(): GameStartAlarmOffset = alarmPreferences.getAlarmOffset()

    override fun setAlarmOffset(offset: GameStartAlarmOffset) {
        alarmPreferences.setAlarmOffset(offset)
    }

    context(scope: ComputationalScope)
    override suspend fun rescheduleGameStartAlarm() {
        val gameInfo = gameInfoSyncService.getCurrentActiveGameInfo()
        videoGameReminderScheduler.scheduleGameStart(gameInfo.gameStartMillis)
    }
}
