package io.paritytech.polkadotapp.feature_wallet_impl.presentation.enterAmount.domain

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.util.fullId
import io.paritytech.polkadotapp.chains.util.planksFromAmount
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.intoAccountId
import io.paritytech.polkadotapp.common.domain.validation.Validation
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.common.utils.filterResultSuccessNotNull
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.flowOf
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.common.utils.mapResult
import io.paritytech.polkadotapp.common.utils.progressStallReport.StalenessReportCollector
import io.paritytech.polkadotapp.common.utils.progressStallReport.markRegion
import io.paritytech.polkadotapp.feature_chats_api.domain.ChatMessageSender
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatId
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessage
import io.paritytech.polkadotapp.feature_coinage_api.domain.debug.CoinageDebugSettings
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.ExternalPaymentPlanner
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.ExternalPaymentService
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.awaitTransferOutcome
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.TransferMemo
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.deriveKeypair
import io.paritytech.polkadotapp.feature_coinage_api.domain.submitter.CoinsSubmitter
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinagePaymentState
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinagePaymentStatus
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinagePaymentStatusUseCase
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.PrepareCoinageTransferUseCase
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.PreparedTransferMemo
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.TotalBalanceUseCase
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.prepareMemo
import io.paritytech.polkadotapp.feature_tokens_api.di.DigitalDollarChainAssetProvider
import io.paritytech.polkadotapp.feature_tokens_api.domain.ChainAssetProvider
import io.paritytech.polkadotapp.feature_transactions.api.data.origins.FreeTransactionOrigins
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.Fee
import io.paritytech.polkadotapp.feature_transfers_api.data.repository.SendRecipientRepository
import io.paritytech.polkadotapp.feature_transfers_api.data.type.TokenTransfersTypeRegistry
import io.paritytech.polkadotapp.feature_transfers_api.domain.model.SendRecipient
import io.paritytech.polkadotapp.feature_transfers_api.domain.model.TransferArguments
import io.paritytech.polkadotapp.feature_wallet_impl.domain.model.AvailableToSendAmount
import io.paritytech.polkadotapp.feature_wallet_impl.domain.model.SendPlan
import io.paritytech.polkadotapp.feature_wallet_impl.domain.model.TransferMethod
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.transformWhile
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import timber.log.Timber
import java.math.BigDecimal
import java.util.concurrent.TimeoutException
import javax.inject.Inject
import kotlin.time.Duration.Companion.seconds
import io.paritytech.polkadotapp.common.R as RCommon

interface SendEnterAmountInteractor {
    val sendValidation: Validation<SendValidationPayload>

    fun tokenBalance(): Flow<AvailableToSendAmount>

    suspend fun asset(): Chain.Asset

    suspend fun estimateFee(recipient: AccountId, value: BigDecimal): Result<Fee>

    /**
     * Reports its progress into [diagnostics]; callers with no UI attached pass
     * [StalenessReportCollector.NoOp].
     */
    context(diagnostics: StalenessReportCollector)
    fun send(value: BigDecimal, transferMethod: TransferMethod): Flow<SendState>

    suspend fun plan(value: BigDecimal, transferMethod: TransferMethod): SendPlan?

    fun observeDebugWidgetsEnabled(): Flow<Boolean>
}

class RealSendEnterAmountInteractor @Inject constructor(
    @param:DigitalDollarChainAssetProvider private val chainAssetProvider: ChainAssetProvider,
    private val transfersTypeRegistry: TokenTransfersTypeRegistry,
    private val sendRecipientRepository: SendRecipientRepository,
    private val freeTransactionOrigins: FreeTransactionOrigins,
    private val chatMessageSender: ChatMessageSender,
    private val prepareCoinageTransferUseCase: PrepareCoinageTransferUseCase,
    private val totalBalanceUseCase: TotalBalanceUseCase,
    private val externalPaymentService: ExternalPaymentService,
    private val externalPaymentPlanner: ExternalPaymentPlanner,
    private val coinsSubmitters: Map<String, @JvmSuppressWildcards CoinsSubmitter>,
    private val coinagePaymentStatusUseCase: CoinagePaymentStatusUseCase,
    private val coinageDebugSettings: CoinageDebugSettings,
    private val coroutineDispatchers: CoroutineDispatchers,
    override val sendValidation: SendValidation
) : SendEnterAmountInteractor {
    companion object {
        private const val WALLET_PAYMENT_ORIGIN = "native-payment"
        private val SETTLEMENT_TIMEOUT = 30.seconds
    }

    override suspend fun asset(): Chain.Asset = chainAssetProvider.asset()

    override fun tokenBalance(): Flow<AvailableToSendAmount> {
        return totalBalanceUseCase.subscribeTotalBalance()
            .mapResult {
                AvailableToSendAmount(
                    spendable = it.availablePrivate,
                    gainingPrivacy = it.gainingPrivacy.amount,
                    canSpendGainingPrivacy = it.gainingPrivacy.canSpendWithConfirmation,
                    chainAsset = asset(),
                )
            }
            .filterResultSuccessNotNull()
    }

    override suspend fun estimateFee(recipient: AccountId, value: BigDecimal): Result<Fee> {
        val asset = asset()

        return transfersTypeRegistry.typeFor(asset)
            .calculateFee(
                TransferArguments(
                    recipient = recipient,
                    amount = value.planksFromAmount(asset.precision),
                    origin = freeTransactionOrigins.freeTxFromWalletOrSigned(asset.chainId)
                )
            )
    }

    context(diagnostics: StalenessReportCollector)
    override fun send(value: BigDecimal, transferMethod: TransferMethod): Flow<SendState> = when (transferMethod) {
        is TransferMethod.CoinsViaChat -> flowOf {
            sendCoinage(transferMethod.recipient, value)
                .onSuccess { rememberRecipient(transferMethod.recipient) }
                .toTerminalState()
        }

        is TransferMethod.UnloadIntoExternal -> flowOf {
            // Note: we don't recall a recipient for external unload
            sendExternalPayment(transferMethod.recipient, value)
                .toTerminalState()
        }

        is TransferMethod.CoinsViaSubmitter -> sendViaSubmitterFlow(transferMethod, value)
    }.flowOn(coroutineDispatchers.computation)

    override suspend fun plan(value: BigDecimal, transferMethod: TransferMethod): SendPlan? = withContext(coroutineDispatchers.computation) {
        when (transferMethod) {
            is TransferMethod.CoinsViaChat,
            is TransferMethod.CoinsViaSubmitter ->
                prepareCoinageTransferUseCase.preparePlan(value).map(SendPlan::Coinage).getOrNull()

            is TransferMethod.UnloadIntoExternal -> {
                val amount = asset().planksFromAmount(value)
                externalPaymentPlanner.plan(amount).getOrNull()?.let(SendPlan::External)
            }
        }
    }

    override fun observeDebugWidgetsEnabled(): Flow<Boolean> = coinageDebugSettings.widgetsEnabledFlow()

    context(diagnostics: StalenessReportCollector)
    private suspend fun sendCoinage(recipient: AccountId, value: BigDecimal): Result<Unit> =
        diagnostics.markRegion(RCommon.string.wallet_stall_sending) {
            prepareCoinageTransferUseCase.prepareMemo(value)
                .map { prepared -> sendChatMessage(recipient, prepared) }
                .onSuccess { Timber.d("CoinageTransfer: Successful") }
                .logFailure("Coinage transfer failed")
        }

    private suspend fun rememberRecipient(recipient: AccountId) {
        sendRecipientRepository.addSendRecipient(SendRecipient(accountId = recipient, fullChainAssetId = asset().fullId))
            .logFailure("Failed to remember send recipient")
    }

    private suspend fun sendExternalPayment(recipient: AccountId, value: BigDecimal): Result<Unit> {
        val amount = asset().planksFromAmount(value)

        return externalPaymentService.initiatePayment(
            origin = WALLET_PAYMENT_ORIGIN,
            amount = amount,
            destination = recipient,
        )
            .flatMap { paymentId -> externalPaymentService.awaitTransferOutcome(WALLET_PAYMENT_ORIGIN, paymentId) }
            .logFailure("External payment failed")
    }

    context(diagnostics: StalenessReportCollector)
    private fun sendViaSubmitterFlow(
        method: TransferMethod.CoinsViaSubmitter,
        value: BigDecimal,
    ): Flow<SendState> = flow {
        val submitter = coinsSubmitters[method.submitterId]
        if (submitter == null) {
            emit(SendState.Failed(IllegalStateException("No CoinsSubmitter registered for '${method.submitterId}'")))
            return@flow
        }

        diagnostics.markRegion(RCommon.string.wallet_stall_sending) {
            prepareCoinageTransferUseCase.prepareMemo(value)
                .flatMap { prepared -> handOverToSubmitter(submitter, prepared, value, method) }
                .logFailure("Coins submission via '${method.submitterId}' failed")
                .onSuccess { memo -> emitAll(settlementStates(memo)) }
                .onFailure { emit(SendState.Failed(it)) }
        }
    }

    context(diagnostics: StalenessReportCollector)
    private suspend fun handOverToSubmitter(
        submitter: CoinsSubmitter,
        prepared: PreparedTransferMemo,
        value: BigDecimal,
        method: TransferMethod.CoinsViaSubmitter,
    ): Result<TransferMemo> = diagnostics.markRegion(RCommon.string.wallet_stall_delivering) {
        submitter.submit(prepared.memo, value, method.submitterPayload)
            // The submitter took the keys, so the handoff is real from here. There is no local
            // transaction to tie this to, unlike the chat path, so the commit is its own step.
            .flatMap { prepared.handoffCommit.commit() }
            .map { prepared.memo }
    }

    /**
     * Follows the handed-over coins until the recipient takes them.
     *
     * The timeout bounds how long the *screen* waits, not the payment: the coins stay ours and stay
     * recoverable however long the recipient takes, so giving up here only stops watching.
     */
    context(diagnostics: StalenessReportCollector)
    private fun settlementStates(memo: TransferMemo): Flow<SendState> = flow {
        val accountIds = memo.coins.map { it.privateKey.deriveKeypair().publicKey.intoAccountId() }

        val completed = diagnostics.markRegion(RCommon.string.wallet_stall_awaiting_claim) {
            withTimeoutOrNull(SETTLEMENT_TIMEOUT) {
                coinagePaymentStatusUseCase.subscribeStatuses(accountIds)
                    .transformWhile { states ->
                        emit(states.toSendState())
                        states.values.any { it.status.isPending }
                    }
                    .catch { error ->
                        if (error is CancellationException) throw error
                        emit(SendState.Failed(error))
                    }
                    .collect { emit(it) }
            }
        }

        if (completed == null) {
            emit(SendState.Failed(TimeoutException("Coins settlement was not confirmed within $SETTLEMENT_TIMEOUT")))
        }
    }

    /**
     * The message row is what carries the keys and what will be delivered from, so it is the moment the
     * handoff becomes real. Committing inside its transaction is the only placement where a crash cannot
     * either strand the coins or release keys a peer already has.
     */
    private suspend fun sendChatMessage(recipient: AccountId, prepared: PreparedTransferMemo) {
        val chatId = ChatId.fromContact(recipient)
        val content = ChatMessage.Content.CoinagePayment(
            totalValue = prepared.memo.totalValue,
            coinKeys = prepared.memo.coins.map { it.privateKey.value },
            status = ChatMessage.Content.CoinagePayment.Status.Detecting
        )
        chatMessageSender.sendUserMessage(
            chatId = chatId,
            content = content,
            onSaved = { prepared.handoffCommit.commit().getOrThrow() },
        )
    }
}

private fun Result<*>.toTerminalState(): SendState = fold(
    onSuccess = { SendState.Complete },
    onFailure = { SendState.Failed(it) }
)

/**
 * Complete only when every coin has been taken: one still on chain means the recipient has not finished, and
 * one not on chain yet means we have not. An empty map is not agreement that nothing is left — it is not
 * knowing yet.
 */
private fun Map<AccountId, CoinagePaymentState>.toSendState(): SendState = when {
    isEmpty() -> SendState.Detecting

    values.any { it.status == CoinagePaymentStatus.AwaitingClaim } -> SendState.Detected

    // Proven claims only: one seen in a best-chain block can be forked away, and this state is final.
    values.all { (it.status as? CoinagePaymentStatus.Claimed)?.finalized == true } -> SendState.Complete

    values.any { it.status == CoinagePaymentStatus.Failed } ->
        SendState.Failed(IllegalStateException("Coins to settle were never minted on chain"))

    else -> SendState.Detecting
}

private val CoinagePaymentStatus.isPending: Boolean
    get() = this == CoinagePaymentStatus.AwaitingClaim || this == CoinagePaymentStatus.Detecting
