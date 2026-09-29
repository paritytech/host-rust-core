package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload

import io.novasama.substrate_sdk_android.runtime.extrinsic.ExtrinsicVersion
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchSignature
import io.paritytech.polkadotapp.chains.di.RemoteSourceQualifier
import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.multiNetwork.connection.ChainConnectionRefCounter
import io.paritytech.polkadotapp.chains.multiNetwork.connection.withConnectionEnabled
import io.paritytech.polkadotapp.chains.network.binding.BlockNumber
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.chains.storage.source.query.api.observeNonNull
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.chains.storage.typed.number
import io.paritytech.polkadotapp.chains.storage.typed.system
import io.paritytech.polkadotapp.common.data.cache.CacheableDataConsistency
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.common.utils.InformationSize.Companion.kilobytes
import io.paritytech.polkadotapp.common.utils.invoke
import io.paritytech.polkadotapp.common.utils.shareInBackground
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_account_api.domain.model.MetaAccount
import io.paritytech.polkadotapp.feature_account_api.domain.model.PersonPublicKey
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.api.candidates
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.api.proofOfInk
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.calls.allocateFull
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.calls.proofOfInk
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.calls.registerNonReferred
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.calls.registerReferred
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.calls.submitEvidenceHash
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.models.ProofOfInkAllocation
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.models.ProofOfInkCandidate
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.model.RawEvidenceChunk
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload.EvidenceUploader.UploadSession
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload.EvidenceUploader.UploadSession.BulletInChainSubscriptions
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload.EvidenceUploader.UploadSession.PeopleChainSubscriptions
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload.EvidenceUploader.UploadSession.Subscriptions
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.signer.proofOfInk.ProofOfInkOriginsFactory
import io.paritytech.polkadotapp.feature_transaction_storage_api.data.calls.store
import io.paritytech.polkadotapp.feature_transaction_storage_api.data.calls.transactionStorage
import io.paritytech.polkadotapp.feature_transaction_storage_api.domain.TransactionStorageRepository
import io.paritytech.polkadotapp.feature_transaction_storage_api.domain.model.TransactionStorageAuthorization
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicExecutionResult
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicService
import io.paritytech.polkadotapp.feature_transactions.api.data.FormExtrinsic
import io.paritytech.polkadotapp.feature_transactions.api.data.origins.SignedOrigins
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.ExtrinsicSubmission
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.TransactionOrigin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import kotlin.coroutines.coroutineContext

interface EvidenceUploader {
    interface UploadSession {
        val chunkingConfig: EvidenceChunkingConfig

        val subscriptions: Deferred<Subscriptions>

        val candidateAccount: MetaAccount

        val peopleChain: Chain

        class Subscriptions(
            val bulletIn: BulletInChainSubscriptions,
            val people: PeopleChainSubscriptions,
        )

        class BulletInChainSubscriptions(
            val blockNumber: Flow<BlockNumber>,
            val authorization: Flow<TransactionStorageAuthorization?>
        )

        class PeopleChainSubscriptions(
            val candidate: Flow<ProofOfInkCandidate?>,
            val blockNumber: Flow<BlockNumber>,
        )

        suspend fun increaseUploadQuota(): Result<ExtrinsicSubmission>

        suspend fun storeEvidence(evidence: RawEvidenceChunk): Result<ExtrinsicSubmission>

        suspend fun submitEvidenceHash(evidenceHash: ByteArray): Result<ExtrinsicSubmission>

        suspend fun registerPersonReferred(
            key: PersonPublicKey,
            rewardDestination: AccountId,
            proofOfOwnership: BandersnatchSignature,
        ): Result<ExtrinsicExecutionResult>

        suspend fun registerPersonNonReferred(
            key: PersonPublicKey,
            rewardDestination: AccountId,
            proofOfOwnership: BandersnatchSignature,
        ): Result<ExtrinsicExecutionResult>

        suspend fun generateProofOfOwnershipMessage(accountId: AccountId): ByteArray
    }

    suspend fun <R> withUploadingSession(block: suspend (UploadSession) -> R): R
}

val PeopleChainSubscriptions.allocation: Flow<ProofOfInkAllocation?>
    get() = candidate.map { it.allocation }

suspend fun UploadSession.isCandidateProven(): Boolean = getCurrentCandidate().isProven

suspend fun UploadSession.getCurrentCandidate(): ProofOfInkCandidate? {
    return subscriptions.await().people.candidate.first()
}

suspend fun UploadSession.getCurrentAllocation(): ProofOfInkAllocation? {
    return getCurrentCandidate().allocation
}

suspend fun UploadSession.getCurrentStorageAuthorization(): TransactionStorageAuthorization? {
    return subscriptions.await().bulletIn.authorization.first()
}

suspend fun UploadSession.requireCurrentStorageAuthorization(): TransactionStorageAuthorization {
    return subscriptions.await().bulletIn.authorization.first()!!
}

suspend fun UploadSession.canIncreaseUploadQuota(): Boolean {
    return getCurrentAllocation().canIncreaseUploadQuota
}

suspend fun UploadSession.isFullAllocation(): Boolean {
    return getCurrentAllocation() == ProofOfInkAllocation.Full
}

suspend fun UploadSession.getCurrentBulletInBlockNumber(): BlockNumber {
    return subscriptions.await().bulletIn.blockNumber.first()
}

class RealEvidenceUploader @Inject constructor(
    private val chainRegistry: ChainRegistry,
    private val accountRepository: AccountRepository,
    private val coroutineDispatchers: CoroutineDispatchers,
    private val poiOriginsFactory: ProofOfInkOriginsFactory,
    private val chainConnectionRefCounter: ChainConnectionRefCounter,
    @RemoteSourceQualifier private val storageDataSource: StorageDataSource,
    private val extrinsicService: ExtrinsicService,
    private val signedOrigins: SignedOrigins,
    private val transactionStorageRepository: TransactionStorageRepository,
) : EvidenceUploader {
    override suspend fun <R> withUploadingSession(block: suspend (UploadSession) -> R): R {
        val bulletInChain = chainRegistry.bulletInChain()
        val peopleChain = chainRegistry.peopleChain()

        val account = accountRepository.getCandidateAccount()

        return chainConnectionRefCounter.withConnectionEnabled(
            setOf(peopleChain.id, bulletInChain.id), "EvidenceUploader"
        ) {
            val session = RealUploadSession(
                bulletInChain = bulletInChain,
                peopleChain = peopleChain,
                candidateAccount = account,
                coroutineScope = CoroutineScope(coroutineContext),
            )

            block(session)
        }
    }

    private inner class RealUploadSession(
        private val bulletInChain: Chain,
        override val peopleChain: Chain,
        override val candidateAccount: MetaAccount,
        private val coroutineScope: CoroutineScope
    ) : UploadSession, CoroutineScope by coroutineScope {
        override val chunkingConfig = EvidenceChunkingConfig(chunkSize = 1536.kilobytes)

        override val subscriptions = async(coroutineDispatchers.io) {
            initSubscriptions()
        }

        private val poiOrigins = async(coroutineDispatchers.io) {
            poiOriginsFactory.createBackground(subscriptions().people.candidate)
        }

        override suspend fun increaseUploadQuota(): Result<ExtrinsicSubmission> {
            return executePeopleChainTx {
                proofOfInk.allocateFull()
            }
        }

        override suspend fun storeEvidence(evidence: RawEvidenceChunk): Result<ExtrinsicSubmission> {
            return executeBulletInChainTx {
                transactionStorage.store(evidence.value)
            }
        }

        override suspend fun submitEvidenceHash(evidenceHash: ByteArray): Result<ExtrinsicSubmission> {
            return executePeopleChainTx {
                proofOfInk.submitEvidenceHash(evidenceHash)
            }
        }

        override suspend fun registerPersonReferred(
            key: PersonPublicKey,
            rewardDestination: AccountId,
            proofOfOwnership: BandersnatchSignature,
        ): Result<ExtrinsicExecutionResult> {
            return executePeopleChainTxAwaitingSuccess {
                proofOfInk.registerReferred(
                    key = key,
                    rewardDestination = rewardDestination,
                    proofOfOwnership = proofOfOwnership
                )
            }
        }

        override suspend fun registerPersonNonReferred(
            key: PersonPublicKey,
            rewardDestination: AccountId,
            proofOfOwnership: BandersnatchSignature,
        ): Result<ExtrinsicExecutionResult> {
            return executePeopleChainTxAwaitingSuccess {
                proofOfInk.registerNonReferred(
                    key = key,
                    rewardDestination = rewardDestination,
                    proofOfOwnership = proofOfOwnership
                )
            }
        }

        override suspend fun generateProofOfOwnershipMessage(accountId: AccountId): ByteArray {
            val prefix = "pop register using".encodeToByteArray()
            return prefix + accountId.value
        }

        private suspend fun executeBulletInChainTx(formExtrinsic: FormExtrinsic): Result<ExtrinsicSubmission> {
            return extrinsicService.submitExtrinsic(
                chain = bulletInChain,
                options = ExtrinsicService.SubmissionOptions(
                    // Bullet-in does not support V5 txs yet
                    extrinsicVersion = ExtrinsicVersion.V4
                ),
                origin = signedOrigins.candidate(),
                formExtrinsic = formExtrinsic,
            )
        }

        private suspend fun executePeopleChainTx(
            formExtrinsic: FormExtrinsic,
        ): Result<ExtrinsicSubmission> {
            return extrinsicService.submitExtrinsic(
                chain = peopleChain,
                origin = postApplyOrigin(),
                formExtrinsic = formExtrinsic
            )
        }

        private suspend fun executePeopleChainTxAwaitingSuccess(
            formExtrinsic: FormExtrinsic,
        ): Result<ExtrinsicExecutionResult> {
            return extrinsicService.submitExtrinsicAndAwaitExecution(
                chain = peopleChain,
                origin = postApplyOrigin(),
                formExtrinsic = formExtrinsic
            )
        }

        private suspend fun initSubscriptions(): Subscriptions {
            return Subscriptions(
                bulletIn = initBulletInSubscriptions(),
                people = initPeopleChainSubscriptions()
            )
        }

        private fun initBulletInSubscriptions(): BulletInChainSubscriptions {
            val accountId = candidateAccount.accountIdIn(bulletInChain)

            return BulletInChainSubscriptions(
                blockNumber = storageDataSource.subscribe(bulletInChain.id) {
                    metadata.system.number.observeNonNull()
                }.shareInBackground(),
                authorization = transactionStorageRepository.subscribeAuthorization(bulletInChain.id, accountId, CacheableDataConsistency.CAN_BE_STALE)
                    .shareInBackground(),
            )
        }

        private fun initPeopleChainSubscriptions(): PeopleChainSubscriptions {
            val accountId = candidateAccount.accountIdIn(peopleChain)

            return PeopleChainSubscriptions(
                candidate = storageDataSource.subscribe(peopleChain.id) {
                    metadata.proofOfInk.candidates.observe(accountId.value)
                }.shareInBackground(),
                blockNumber = storageDataSource.subscribe(peopleChain.id) {
                    metadata.system.number.observeNonNull()
                }.shareInBackground()
            )
        }

        private suspend fun postApplyOrigin(): TransactionOrigin {
            return poiOrigins().postApplyOrigin(peopleChain)
        }
    }
}

private val ProofOfInkAllocation?.canIncreaseUploadQuota
    get() = this == ProofOfInkAllocation.InitDone

private val ProofOfInkCandidate?.allocation: ProofOfInkAllocation?
    get() = if (this is ProofOfInkCandidate.Selected) allocation else null

val ProofOfInkCandidate?.isProven: Boolean
    get() = this is ProofOfInkCandidate.Proven
