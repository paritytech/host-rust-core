package io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase

import io.novasama.substrate_sdk_android.encrypt.keypair.Keypair
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.common.utils.coerceToUnit
import io.paritytech.polkadotapp.common.utils.flattenResult
import io.paritytech.polkadotapp.common.utils.mapAsync
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.ValueExponent
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.CoinageTransactionService
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageOperationGroupId
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionRequest
import io.paritytech.polkadotapp.feature_coinage_impl.data.blockchain.coinage
import io.paritytech.polkadotapp.feature_coinage_impl.data.blockchain.transfer
import io.paritytech.polkadotapp.feature_coinage_impl.data.model.OnChainCoinInfo
import io.paritytech.polkadotapp.feature_coinage_impl.data.signer.origins.CoinageTransactionOrigins
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogD
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogW
import io.paritytech.polkadotapp.feature_coinage_impl.domain.model.CoinageTransaction
import io.paritytech.polkadotapp.feature_coinage_impl.domain.model.mintCoin
import io.paritytech.polkadotapp.feature_tokens_api.di.DigitalDollarChainAssetProvider
import io.paritytech.polkadotapp.feature_tokens_api.domain.ChainAssetProvider
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicService
import javax.inject.Inject

interface CoinageTransferSubmissionUseCase {
    /**
     * Register a transfer of requested coins into freshly created accounts
     * This does not perform any retries and returns as soon as **registration** is completed
     * Status monitoring should be done via [CoinageTransactionService.subscribeOperationGroupStatuses] for the given [groupId]
     */
    suspend operator fun invoke(
        keyPairs: List<Keypair>,
        coinsInfo: Map<AccountId, OnChainCoinInfo>,
        groupId: CoinageOperationGroupId,
    ): Result<Unit>
}

/**
 * Claims coins a peer handed us: each one is transferred to a fresh address of ours.
 *
 * The peer's key is a `Received` input — never a local asset — so the ledger can hold it against exactly one
 * claim without us ever having minted it.
 */
class RealCoinageTransferSubmissionUseCase @Inject constructor(
    @param:DigitalDollarChainAssetProvider private val chainAssetProvider: ChainAssetProvider,
    private val coinageTransactionOrigins: CoinageTransactionOrigins,
    private val extrinsicService: ExtrinsicService,
    private val transactionService: CoinageTransactionService,
    private val coinageTransactionFactory: CoinageTransaction.Factory,
) : CoinageTransferSubmissionUseCase {
    override suspend operator fun invoke(
        keyPairs: List<Keypair>,
        coinsInfo: Map<AccountId, OnChainCoinInfo>,
        groupId: CoinageOperationGroupId,
    ): Result<Unit> {
        val claims = keyPairs.mapAsync { keyPair ->
            val accountId = keyPair.publicKey.toDataByteArray()

            coinsInfo[accountId]?.let { info ->
                buildClaim(ValueExponent(info.value), keyPair, groupId)
            } ?: run {
                coinageLogW("Claim skipped, no coin on chain group=${groupId.value} coin=$accountId")
                Result.success(null)
            }
        }
            .flattenResult()
            .getOrElse { return Result.failure(it) }
            .filterNotNull()

        if (claims.isEmpty()) return Result.success(Unit)

        coinageLogD("Claims registering group=${groupId.value} claims=${claims.size}")

        return transactionService.submitTransactions(claims, groupId).coerceToUnit()
    }

    /**
     * Each claim is signed by the peer's own key, so these cannot be one nonce-sequenced batch the way a
     * group of our own transactions can. They are built independently and registered together, which is what
     * the ledger cares about: either the whole claim group is recorded or none of it is.
     */
    private suspend fun buildClaim(
        valueExponent: ValueExponent,
        keypair: Keypair,
        groupId: CoinageOperationGroupId,
    ): Result<CoinageTransactionRequest> {
        val chain = chainAssetProvider.chain()
        val transaction = coinageTransactionFactory.newTransaction()
        val source = keypair.publicKey.toDataByteArray()

        val destination = transaction.mintCoin(valueExponent).getOrElse { return Result.failure(it) }
        transaction.consumeReceivedCoin(source)
        val assets = transaction.build()

        coinageLogD("Claim built group=${groupId.value} coin=$source value=${valueExponent.value}")

        return extrinsicService.buildExtrinsic(
            chain = chain,
            origin = coinageTransactionOrigins.createAsCoinOrigin(keypair),
            options = ExtrinsicService.SubmissionOptions(),
            formExtrinsic = { coinage.transfer(destination.accountId) },
        ).map { extrinsic ->
            CoinageTransactionRequest(extrinsic = extrinsic, inputs = assets.inputs, outputs = assets.outputs)
        }
    }
}
