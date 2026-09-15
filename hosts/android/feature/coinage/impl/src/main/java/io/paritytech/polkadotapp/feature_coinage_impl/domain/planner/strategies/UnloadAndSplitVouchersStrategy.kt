package io.paritytech.polkadotapp.feature_coinage_impl.domain.planner.strategies

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchAlias
import io.paritytech.polkadotapp.bandersnatch_crypto.aliasInContext
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.chains.network.binding.BlockHash
import io.paritytech.polkadotapp.chains.repository.ChainStateRepository
import io.paritytech.polkadotapp.chains.util.EncodedArguments.Companion.autoEncodedArgs
import io.paritytech.polkadotapp.chains.util.call
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.common.utils.mapIndexedAsync
import io.paritytech.polkadotapp.common.utils.progressStallReport.StalenessReportCollector
import io.paritytech.polkadotapp.common.utils.progressStallReport.markRegion
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.Coin
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RecyclerKey
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RecyclerVoucher
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.StrategyType
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.isInRecycler
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.CoinageTransactionService
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageHandoffCommit
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageOperationGroupId
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionRequest
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.OwnAsset
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinAmountBreakdownUseCase
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinageBalanceConverterUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.data.config.CoinageInstanceIdProvider
import io.paritytech.polkadotapp.feature_coinage_impl.data.derivation.VoucherRingDerivation
import io.paritytech.polkadotapp.feature_coinage_impl.data.helpers.FreeUnloadTokenResolver
import io.paritytech.polkadotapp.feature_coinage_impl.data.helpers.UnloadTokenResolverFactory
import io.paritytech.polkadotapp.feature_coinage_impl.data.helpers.createForCollection
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.CoinRepository
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.RecyclerProofDataProvider
import io.paritytech.polkadotapp.feature_coinage_impl.data.signer.context.CoinageSigningContextProvider
import io.paritytech.polkadotapp.feature_coinage_impl.data.signer.origins.CoinageTransactionOrigins
import io.paritytech.polkadotapp.feature_coinage_impl.domain.model.CoinageTransaction
import io.paritytech.polkadotapp.feature_coinage_impl.domain.model.CoinageTransactionAssets
import io.paritytech.polkadotapp.feature_coinage_impl.domain.model.mintAndHandOffCoins
import io.paritytech.polkadotapp.feature_coinage_impl.domain.model.toSplitDestinations
import io.paritytech.polkadotapp.feature_coinage_impl.domain.recycling.UnloadQuotaTracker
import io.paritytech.polkadotapp.feature_members_api.data.model.RingRevision
import io.paritytech.polkadotapp.feature_people_api.domain.PeopleCollection
import io.paritytech.polkadotapp.feature_people_api.domain.PeopleMembershipProver
import io.paritytech.polkadotapp.feature_people_api.domain.PrecomputedPersonMembershipProver
import io.paritytech.polkadotapp.feature_transactions.api.data.EnrichedSendableExtrinsic
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicService
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.TransactionOrigin
import javax.inject.Inject
import io.paritytech.polkadotapp.common.R as RCommon

class UnloadAndSplitVouchersStrategyFactory @Inject constructor(
    private val chainStateRepository: ChainStateRepository,
    private val originFactory: CoinageTransactionOrigins,
    private val coinageSigningContextProvider: CoinageSigningContextProvider,
    private val voucherRingDerivation: VoucherRingDerivation,
    private val recyclerProofDataProvider: RecyclerProofDataProvider,
    private val unloadTokenResolverFactory: UnloadTokenResolverFactory,
    private val coinRepository: CoinRepository,
    private val extrinsicService: ExtrinsicService,
    private val transactionService: CoinageTransactionService,
    private val coinageTransactionFactory: CoinageTransaction.Factory,
    private val breakdownUseCase: CoinAmountBreakdownUseCase,
    private val balanceConverterUseCase: CoinageBalanceConverterUseCase,
    private val peopleMembershipProver: PeopleMembershipProver,
    private val quotaTracker: UnloadQuotaTracker,
    private val coinageInstanceIdProvider: CoinageInstanceIdProvider
) {
    fun create(
        payload: StrategyType.UnloadAndSplit,
        peopleCollection: PeopleCollection,
        chain: Chain,
    ) = UnloadAndSplitVouchersStrategy(
        originFactory = originFactory,
        payload = payload,
        coinageSigningContextProvider = coinageSigningContextProvider,
        voucherRingDerivation = voucherRingDerivation,
        recyclerProofDataProvider = recyclerProofDataProvider,
        freeUnloadTokenResolver = unloadTokenResolverFactory.createForCollection(peopleCollection),
        peopleCollection = peopleCollection,
        chain = chain,
        chainStateRepository = chainStateRepository,
        coinRepository = coinRepository,
        extrinsicService = extrinsicService,
        transactionService = transactionService,
        coinageTransactionFactory = coinageTransactionFactory,
        breakdownUseCase = breakdownUseCase,
        balanceConverterUseCase = balanceConverterUseCase,
        peopleMembershipProver = peopleMembershipProver,
        quotaTracker = quotaTracker,
        coinageInstanceIdProvider = coinageInstanceIdProvider
    )
}

class UnloadAndSplitVouchersStrategy(
    payload: StrategyType.UnloadAndSplit,
    private val chainStateRepository: ChainStateRepository,
    private val originFactory: CoinageTransactionOrigins,
    private val peopleCollection: PeopleCollection,
    private val coinageSigningContextProvider: CoinageSigningContextProvider,
    private val voucherRingDerivation: VoucherRingDerivation,
    private val recyclerProofDataProvider: RecyclerProofDataProvider,
    private val freeUnloadTokenResolver: FreeUnloadTokenResolver,
    private val chain: Chain,
    private val coinRepository: CoinRepository,
    private val extrinsicService: ExtrinsicService,
    private val transactionService: CoinageTransactionService,
    private val coinageTransactionFactory: CoinageTransaction.Factory,
    private val breakdownUseCase: CoinAmountBreakdownUseCase,
    private val balanceConverterUseCase: CoinageBalanceConverterUseCase,
    private val peopleMembershipProver: PeopleMembershipProver,
    private val quotaTracker: UnloadQuotaTracker,
    private val coinageInstanceIdProvider: CoinageInstanceIdProvider
) : TransferStrategy {
    private val vouchers = payload.vouchersToUnload
    private val recipientAmount = payload.recipientAmount
    private val exactCoins = payload.exactCoins

    /**
     * One group of transactions, one per voucher batch.
     *
     * Every extrinsic is built before any is registered, each is then
     * registered and submitted on its own. A crash part-way leaves the registered ones to reach FAILURE at
     * mortality and return their vouchers, and the unregistered ones never reserved anything.
     */
    context(diagnostics: StalenessReportCollector)
    override suspend fun run(): Result<PreparedTransfer> = diagnostics.markRegion(RCommon.string.coinage_stall_preparing_transfer) {
        runCatching {
            require(vouchers.isNotEmpty()) { "TransferStrategyError.emptyVouchers" }
            require(vouchers.all { it.isInRecycler() }) { "TransferStrategyError.missingRecyclerInfo" }

            val unloadContext = resolveUnloadContext()
            val freeUnloadTokens = resolveFreeUnloadTokens(unloadContext.batches.size)
            val personProver = precomputePersonProver(unloadContext.pinnedBlockHash)

            val prepared = buildBatches(unloadContext, freeUnloadTokens, personProver)

            val handedOffExactCoins = exactCoins.map { OwnAsset.Coin(it.derivationIndex) }
            val handoffCommit = submitBatches(prepared, handedOffExactCoins)

            // After submission, not after resolving: a token picked for a transaction that never left is still
            // there to be picked again.
            quotaTracker.noteUnloadsHappened(freeUnloadTokens.size)

            PreparedTransfer((exactCoins + prepared.flatMap { it.recipientCoins }).toMemoEntries(), handoffCommit)
        }
    }

    context(diagnostics: StalenessReportCollector)
    private suspend fun resolveUnloadContext(): UnloadContext = diagnostics.markRegion(RCommon.string.stall_reading_chain_state) {
        val batches = resolveBatches()

        val pinnedBlockHash = chainStateRepository.currentBlockHash(chain.id)
        val groupRevisions = recyclerProofDataProvider
            .getRecyclerRevisions(chain.id, batches.map { it.recyclerKey }, pinnedBlockHash)
            .logFailure("Failed to get recycler revisions")
            .getOrThrow()

        UnloadContext(batches, pinnedBlockHash, groupRevisions)
    }

    context(diagnostics: StalenessReportCollector)
    private suspend fun resolveFreeUnloadTokens(batchCount: Int): List<FreeUnloadTokenResolver.ResolvedUnloadToken> =
        diagnostics.markRegion(RCommon.string.coinage_stall_picking_unload_token) {
            freeUnloadTokenResolver.resolve(chain.id, batchCount)
        }

    /**
     * One prover for the whole transfer: every batch proves the same person against the same pinned block, so
     * the ring lookups behind it are paid once instead of once per extrinsic.
     */
    context(diagnostics: StalenessReportCollector)
    private suspend fun precomputePersonProver(pinnedBlockHash: BlockHash): PrecomputedPersonMembershipProver =
        diagnostics.markRegion(RCommon.string.coinage_stall_reading_anonymity_set) {
            peopleMembershipProver.precomputeForMember(
                chainId = chain.id,
                peopleCollection = peopleCollection,
                at = pinnedBlockHash,
            ).getOrThrow()
        }

    /**
     * The ring-VRF proofs each extrinsic carries are produced lazily while it is being built, and they are the
     * slowest thing in the transfer. The batches run concurrently, so one region covers the whole fan-out
     * rather than one row per batch.
     */
    context(diagnostics: StalenessReportCollector)
    private suspend fun buildBatches(
        unloadContext: UnloadContext,
        freeUnloadTokens: List<FreeUnloadTokenResolver.ResolvedUnloadToken>,
        personProver: PrecomputedPersonMembershipProver,
    ): List<PreparedBatch> = diagnostics.markRegion(RCommon.string.coinage_stall_generating_proofs) {
        unloadContext.batches.mapIndexedAsync { index, batch ->
            val transaction = coinageTransactionFactory.newTransaction()
            val outputs = transaction.mintGroupOutputs(batch)

            PreparedBatch(
                assets = transaction.build(),
                recipientCoins = outputs.recipient,
                extrinsic = buildExtrinsic(
                    batch = batch,
                    outputCoins = outputs.all,
                    unloadToken = freeUnloadTokens[index],
                    personProver = personProver,
                    recyclerRevisionBlockHash = unloadContext.pinnedBlockHash,
                    revision = unloadContext.groupRevisions.getValue(batch.recyclerKey),
                ).getOrThrow(),
            )
        }
    }

    context(diagnostics: StalenessReportCollector)
    private suspend fun submitBatches(
        prepared: List<PreparedBatch>,
        handedOffExactCoins: List<OwnAsset.Coin>,
    ): CoinageHandoffCommit = diagnostics.markRegion(RCommon.string.stall_submitting_transaction) {
        val groupId = CoinageOperationGroupId.generateNew()

        val handoffCommit = transactionService
            .preCommitHandoff(handedOffExactCoins + prepared.flatMap { it.assets.handedOff })
            .getOrThrow()

        val requests = prepared.map { batch ->
            CoinageTransactionRequest(
                extrinsic = batch.extrinsic,
                inputs = batch.assets.inputs,
                outputs = batch.assets.outputs,
            )
        }

        transactionService.submitTransactions(requests, groupId).getOrThrow()

        handoffCommit
    }

    private class UnloadContext(
        val batches: List<VoucherBatch>,
        val pinnedBlockHash: BlockHash,
        val groupRevisions: Map<RecyclerKey, RingRevision>,
    )

    private class PreparedBatch(
        val assets: CoinageTransactionAssets,
        val recipientCoins: List<Coin>,
        val extrinsic: EnrichedSendableExtrinsic,
    )

    private suspend fun resolveBatches(): List<VoucherBatch> {
        val breakdown = breakdownUseCase.createCoinAmountBreakdown().getOrThrow()
        val conversionContext = balanceConverterUseCase.create().getOrThrow()
        val maxConsolidation = coinRepository.fetchMaxConsolidation(chain.id).getOrThrow()

        return VoucherBatchDistribution.distribute(
            vouchers = vouchers,
            recipientAmount = recipientAmount,
            maxConsolidation = maxConsolidation,
            breakdown = breakdown,
            conversionContext = conversionContext
        )
    }

    private suspend fun CoinageTransaction.mintGroupOutputs(batch: VoucherBatch): TransferOutputs {
        useVouchers(batch.vouchers)
        val recipientCoins = mintAndHandOffCoins(batch.recipientDenominations).getOrThrow()
        val changeCoins = mintCoins(batch.changeDenominations).getOrThrow()
        return TransferOutputs(recipientCoins, changeCoins)
    }

    private suspend fun buildExtrinsic(
        batch: VoucherBatch,
        outputCoins: List<Coin>,
        unloadToken: FreeUnloadTokenResolver.ResolvedUnloadToken,
        personProver: PrecomputedPersonMembershipProver,
        recyclerRevisionBlockHash: BlockHash,
        revision: RingRevision
    ) = coinageInstanceIdProvider.instanceId().flatMap { instanceId ->
        val destinations = outputCoins.toSplitDestinations()
        val origin = makeOriginDefinition(batch.vouchers, unloadToken, recyclerRevisionBlockHash, personProver)
        val aliases = buildAliases(batch.vouchers)

        extrinsicService.buildExtrinsic(
            chain = chain,
            origin = origin,
            options = ExtrinsicService.SubmissionOptions(),
            formExtrinsic = {
                call(
                    moduleName = "Coinage",
                    callName = "unload_recycler_into_coins",
                    arguments = autoEncodedArgs(
                        "instance_id" to instanceId.toLong(),
                        "aliases" to aliases,
                        "value" to batch.recyclerKey.exponent,
                        "index" to batch.recyclerKey.recyclerIndex,
                        "revision" to revision,
                        "split_into" to destinations,
                        "max_fee" to Balance.ZERO,
                    ),
                )
            },
        )
    }

    private suspend fun buildAliases(vouchers: List<RecyclerVoucher>): List<BandersnatchAlias> {
        val aliasContext = coinageSigningContextProvider.recyclerVouchersContext()

        return vouchers.map { voucher ->
            voucherRingDerivation.deriveBandersnatch(voucher.ringVrfKeyIndex)
                .aliasInContext(aliasContext)
        }
    }

    private fun makeOriginDefinition(
        vouchers: List<RecyclerVoucher>,
        resolvedUnloadToken: FreeUnloadTokenResolver.ResolvedUnloadToken,
        recyclerRevisionBlockHash: BlockHash,
        personProver: PrecomputedPersonMembershipProver,
    ): TransactionOrigin {
        return originFactory.createAsUnloadTokenPeopleOrigin(
            vouchers = vouchers,
            resolvedUnloadToken = resolvedUnloadToken,
            recyclerRevisionBlockHash = recyclerRevisionBlockHash,
            personProver = personProver,
            peopleCollection = peopleCollection,
        )
    }
}
