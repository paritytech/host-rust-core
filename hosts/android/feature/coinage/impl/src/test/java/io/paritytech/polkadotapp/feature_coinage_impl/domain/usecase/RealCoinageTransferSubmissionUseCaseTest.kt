package io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase

import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.novasama.substrate_sdk_android.encrypt.keypair.Keypair
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.Coin
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.ValueExponent
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.CoinageTransactionService
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageInput
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageOperationGroupId
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionId
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionRequest
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.OwnAsset
import io.paritytech.polkadotapp.feature_coinage_impl.data.model.OnChainCoinInfo
import io.paritytech.polkadotapp.feature_coinage_impl.data.signer.origins.CoinageTransactionOrigins
import io.paritytech.polkadotapp.feature_coinage_impl.domain.model.CoinageTransaction
import io.paritytech.polkadotapp.feature_coinage_impl.domain.model.CoinageTransactionAssets
import io.paritytech.polkadotapp.feature_tokens_api.domain.ChainAssetProvider
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicService
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Claiming coins a peer handed us: one transaction per key, each minting a fresh coin of ours and consuming
 * the peer's key as a received input.
 *
 * The peer's key is never one of our assets, so nothing here may register it as one — that is what lets the
 * ledger hold it against exactly one claim without us having minted it.
 */
class RealCoinageTransferSubmissionUseCaseTest {
    private val chainAssetProvider: ChainAssetProvider = mockk(relaxed = true)
    private val origins: CoinageTransactionOrigins = mockk(relaxed = true)
    private val extrinsicService: ExtrinsicService = mockk()
    private val transactionService: CoinageTransactionService = mockk()
    private val transactionFactory: CoinageTransaction.Factory = mockk()

    private val useCase = RealCoinageTransferSubmissionUseCase(
        chainAssetProvider = chainAssetProvider,
        coinageTransactionOrigins = origins,
        extrinsicService = extrinsicService,
        transactionService = transactionService,
        coinageTransactionFactory = transactionFactory,
    )

    private val groupId = CoinageOperationGroupId("claim")
    private val registrations = mutableListOf<List<CoinageTransactionRequest>>()
    private val registeredGroups = mutableListOf<CoinageOperationGroupId>()

    /** One batch per call, so a group's claims are whatever that single call carried. */
    private val claims: List<CoinageTransactionRequest> get() = registrations.single()

    /**
     * A peer sends two keys but only one coin has appeared on chain.
     * The key with nothing behind it is skipped rather than claimed.
     * The call still succeeds: a coin that never arrives is the peer's problem, and refusing the whole
     * payment over it would strand the coin that did arrive.
     */
    @Test
    fun `a key with no coin on chain is skipped rather than claimed`() = runBlocking<Unit> {
        val present = keypairOf(1)
        val missing = keypairOf(2)
        givenTransactionMints(Coin(derivationIndex = 9, valueExponent = ValueExponent(3), age = Coin.Age.Unknown, isOnChain = false, accountId = ACCOUNT))
        givenExtrinsicBuilds()
        givenSubmissionSucceeds()

        val result = useCase(listOf(present, missing), mapOf(present.accountId() to OnChainCoinInfo(instanceId = 0, value = 3, age = 0)), groupId)

        assertTrue(result.isSuccess)
        assertEquals(1, claims.size)
    }

    @Test
    fun `every claim is registered together, under the group the caller passed`() = runBlocking<Unit> {
        val keypairs = listOf(keypairOf(1), keypairOf(2))
        givenTransactionMints(Coin(derivationIndex = 9, valueExponent = ValueExponent(3), age = Coin.Age.Unknown, isOnChain = false, accountId = ACCOUNT))
        givenExtrinsicBuilds()
        givenSubmissionSucceeds()

        useCase(keypairs, keypairs.associate { it.accountId() to OnChainCoinInfo(instanceId = 0, value = 3, age = 0) }, groupId)

        assertEquals(2, claims.size)
        assertEquals(listOf(groupId), registeredGroups)
    }

    /** The peer's key goes in as a received input, and the coin we mint is the only output of ours. */
    @Test
    fun `a claim consumes the peer's key and mints a coin of ours`() = runBlocking<Unit> {
        val keypair = keypairOf(1)
        val minted = Coin(derivationIndex = 9, valueExponent = ValueExponent(3), age = Coin.Age.Unknown, isOnChain = false, accountId = ACCOUNT)
        givenTransactionMints(minted)
        givenExtrinsicBuilds()
        givenSubmissionSucceeds()

        useCase(listOf(keypair), mapOf(keypair.accountId() to OnChainCoinInfo(instanceId = 0, value = 3, age = 0)), groupId)

        assertEquals(listOf(CoinageInput.Coin.Received(keypair.accountId())), claims.single().inputs)
        assertEquals(listOf(OwnAsset.Coin(minted.derivationIndex)), claims.single().outputs)
    }

    @Test
    fun `a claim whose extrinsic cannot be built fails the call`() = runBlocking<Unit> {
        val keypair = keypairOf(1)
        givenTransactionMints(Coin(derivationIndex = 9, valueExponent = ValueExponent(3), age = Coin.Age.Unknown, isOnChain = false, accountId = ACCOUNT))
        coEvery { extrinsicService.buildExtrinsic(any(), any(), any(), any()) } returns
            Result.failure(IllegalStateException("no runtime"))

        val result = useCase(listOf(keypair), mapOf(keypair.accountId() to OnChainCoinInfo(instanceId = 0, value = 3, age = 0)), groupId)

        assertTrue(result.isFailure)
        coVerify(exactly = 0) { transactionService.submitTransactions(any(), any()) }
    }

    @Test
    fun `a claim the ledger refuses fails the call`() = runBlocking<Unit> {
        val keypair = keypairOf(1)
        givenTransactionMints(Coin(derivationIndex = 9, valueExponent = ValueExponent(3), age = Coin.Age.Unknown, isOnChain = false, accountId = ACCOUNT))
        givenExtrinsicBuilds()
        coEvery { transactionService.submitTransactions(any(), any()) } returns
            Result.failure(IllegalStateException("already claimed"))

        val result = useCase(listOf(keypair), mapOf(keypair.accountId() to OnChainCoinInfo(instanceId = 0, value = 3, age = 0)), groupId)

        assertTrue(result.isFailure)
    }

    @Test
    fun `a claim whose coin cannot be minted fails the call`() = runBlocking<Unit> {
        val keypair = keypairOf(1)
        val transaction: CoinageTransaction = mockk(relaxed = true)
        every { transactionFactory.newTransaction() } returns transaction
        coEvery { transaction.mintCoins(any()) } returns Result.failure(IllegalStateException("no key slot"))

        val result = useCase(listOf(keypair), mapOf(keypair.accountId() to OnChainCoinInfo(instanceId = 0, value = 3, age = 0)), groupId)

        assertTrue(result.isFailure)
        coVerify(exactly = 0) { transactionService.submitTransactions(any(), any()) }
    }

    private fun givenTransactionMints(coin: Coin) {
        val transaction: CoinageTransaction = mockk(relaxed = true)

        every { transactionFactory.newTransaction() } returns transaction
        coEvery { transaction.mintCoins(any()) } returns Result.success(listOf(coin))
        every { transaction.build() } answers {
            CoinageTransactionAssets(
                inputs = consumedKeys.map { CoinageInput.Coin.Received(it) },
                outputs = listOf(OwnAsset.Coin(coin.derivationIndex)),
                handedOff = emptyList(),
            )
        }
        every { transaction.consumeReceivedCoin(any()) } answers { consumedKeys = listOf(firstArg()) }
    }

    private var consumedKeys: List<AccountId> = emptyList()

    private fun givenExtrinsicBuilds() {
        coEvery { extrinsicService.buildExtrinsic(any(), any(), any(), any()) } returns Result.success(mockk())
    }

    private fun givenSubmissionSucceeds() {
        coEvery { transactionService.submitTransactions(any(), any()) } answers {
            registrations += arg<List<CoinageTransactionRequest>>(0)
            // A value class over String arrives unboxed at the mock boundary.
            registeredGroups += CoinageOperationGroupId(arg(1))

            Result.success(registrations.indices.map { CoinageTransactionId(it.toLong()) })
        }
    }

    private fun keypairOf(seed: Int): Keypair = mockk<Keypair>().also {
        every { it.publicKey } returns byteArrayOf(seed.toByte())
    }

    private fun Keypair.accountId(): AccountId = publicKey.toDataByteArray()

    private companion object {
        val ACCOUNT: AccountId = byteArrayOf(7).toDataByteArray()
    }
}
