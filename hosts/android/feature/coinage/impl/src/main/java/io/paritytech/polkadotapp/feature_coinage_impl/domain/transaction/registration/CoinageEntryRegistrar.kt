package io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.registration

import io.novasama.substrate_sdk_android.extensions.toHexString
import io.novasama.substrate_sdk_android.runtime.definitions.types.generics.DefaultSignedExtensions
import io.novasama.substrate_sdk_android.runtime.definitions.types.generics.Era
import io.novasama.substrate_sdk_android.runtime.definitions.types.generics.findExplicitOrNull
import io.novasama.substrate_sdk_android.runtime.extrinsic.signer.SendableExtrinsic
import io.paritytech.polkadotapp.chains.util.extrinsicHash
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CheckpointBlock
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageHandoffCommit
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageInput
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageOperationGroupId
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageRegistrationError
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionId
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionRequest
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.OwnAsset
import io.paritytech.polkadotapp.feature_coinage_impl.data.derivation.CoinKeypairDerivation
import io.paritytech.polkadotapp.feature_coinage_impl.data.derivation.VoucherRingDerivation
import io.paritytech.polkadotapp.feature_coinage_impl.data.derivation.getDerivedAccountId
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.AssetPublicKey
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.CoinageAssetKind
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.CoinageEntryRepository
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.EntryRegistration
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.LedgerAsset
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.RegistrationInput
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.RegistrationOutput
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.RegistrationValidationScope
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogI
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogW
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.coinageLogId
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.shortKey
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.submission.SubmissionOwnedEntries
import io.paritytech.polkadotapp.feature_transactions.api.data.EnrichedSendableExtrinsic
import javax.inject.Inject

/**
 * The only thing that adds entries, and the only place the four invariants are enforced.
 *
 * The window an entry is recovered against is the extrinsic's own: its `CheckMortality` era is what the
 * runtime will actually enforce, so anchoring to anything else would search a range the extrinsic could not
 * have landed in. Only extrinsics this app built are registrable, and each reports the block its era was
 * anchored to, so the window is read off the request rather than re-derived from the chain.
 *
 * Reads nothing from the chain at all: only our own entries consume our own assets and every one of them is
 * in the ledger, so the invariants already exclude every asset we have committed and every asset a peer can
 * spend. A presence read would add only the case where an input is missing for a reason outside our control
 * — where the cost is a failed dispatch the rules resolve — while rejecting the ordinary received payment,
 * whose key is registrable before the peer's transfer has even been included.
 */
class CoinageEntryRegistrar @Inject constructor(
    private val repository: CoinageEntryRepository,
    private val coinKeypairDerivation: CoinKeypairDerivation,
    private val voucherRingDerivation: VoucherRingDerivation,
    private val submissionOwnedEntries: SubmissionOwnedEntries,
) {
    suspend fun register(
        extrinsic: EnrichedSendableExtrinsic,
        inputs: List<CoinageInput>,
        outputs: List<OwnAsset>,
        groupId: CoinageOperationGroupId?,
    ): Result<CoinageTransactionId> {
        val request = CoinageTransactionRequest(extrinsic, inputs, outputs)
        val registration = prepare(listOf(request), groupId).getOrElse {
            logRejected(it)

            return Result.failure(it)
        }

        return repository.registerValidated(
            request = registration.single(),
            validation = { validate(registration) },
            // Ownership is taken inside the same transaction, so a committed row always has an owner and a
            // pass can never reach it before the watcher does.
            onCommitted = { id -> submissionOwnedEntries.acquire(id) },
        )
            .onSuccess { id -> coinageLogI("entry-registered ${registration.single().describe(id)}") }
            .onFailure(::logRejected)
    }

    /** All of [requests] or none of them, so [groupId] never holds half an operation. */
    suspend fun registerAll(
        requests: List<CoinageTransactionRequest>,
        groupId: CoinageOperationGroupId,
    ): Result<List<CoinageTransactionId>> {
        val registrations = prepare(requests, groupId).getOrElse {
            logRejected(it)

            return Result.failure(it)
        }

        return repository.registerAllValidated(
            requests = registrations,
            validation = { validate(registrations) },
            onCommitted = { ids -> ids.forEach { submissionOwnedEntries.acquire(it) } },
        )
            .onSuccess { ids ->
                ids.zip(registrations).forEach { (id, registration) ->
                    coinageLogI("entry-registered ${registration.describe(id)}")
                }
            }
            .onFailure(::logRejected)
    }

    private suspend fun prepare(
        requests: List<CoinageTransactionRequest>,
        groupId: CoinageOperationGroupId?,
    ): Result<List<EntryRegistration>> {
        requests.firstOrNull { it.inputs.isEmpty() && it.outputs.isEmpty() }?.let {
            return Result.failure(CoinageRegistrationError.EmptyTransaction)
        }

        return runCatching {
            requests.map { request ->
                val era = request.extrinsic.mortalEra() ?: throw CoinageRegistrationError.NotMortal

                EntryRegistration(
                    txHash = request.extrinsic.extrinsicHex.extrinsicHash(),
                    checkpoint = request.extrinsic.signedCheckpoint(),
                    mortalityBlocks = era.period.toLong(),
                    groupId = groupId,
                    inputs = request.inputs.map { RegistrationInput(it, it.publicKey()) },
                    outputs = request.outputs.map { RegistrationOutput(it, it.publicKey()) },
                )
            }
        }
    }

    /**
     * The anchor the extrinsic was signed over, as the builder reported it. This is the only source for the
     * window: re-deriving it from a finalized head read at registration time can name a different block once
     * the head has crossed a period boundary, and the era alone cannot tell those occurrences apart.
     */
    private fun EnrichedSendableExtrinsic.signedCheckpoint(): CheckpointBlock {
        val blockNumber = mortality.eraBlockNumber ?: throw CoinageRegistrationError.MissingEraAnchor

        return CheckpointBlock(
            blockNumber = blockNumber,
            blockHash = mortality.blockHash.value.toHexString(withPrefix = true)
        )
    }

    /** Runs inside the write transaction, so nothing can move what it checked. */
    private suspend fun RegistrationValidationScope.validate(registrations: List<EntryRegistration>) {
        brokenInvariant(registrations)?.let { throw it }
    }

    private suspend fun RegistrationValidationScope.brokenInvariant(
        registrations: List<EntryRegistration>,
    ): CoinageRegistrationError? {
        val outputs = registrations.flatMap { it.outputs }
        val inputs = registrations.flatMap { it.inputs }

        val outputKeys = outputs.map { it.publicKey }
        val inputKeys = inputs.map { it.publicKey }

        // Fresh outputs: an output address is an output of no other entry, and not a key a peer sent us.
        // Within the batch too, for the same reason the unique-consumer check below covers it.
        val notFresh = filterMinted(outputKeys) + filterReceived(outputKeys) + outputKeys.duplicates()
        outputs.firstOrNull { it.publicKey in notFresh }?.let {
            return CoinageRegistrationError.OutputNotFresh(it.output)
        }

        // Blocked handoff: a handed-off asset is never an input.
        val handedOff = filterHandedOff(inputKeys)
        inputs.firstOrNull { it.publicKey in handedOff }?.let {
            return CoinageRegistrationError.InputHandedOff(it.input)
        }

        // Unique consumer: an asset is an input of at most one entry that is not a failure. Within the batch
        // too — these rows do not exist yet, so the queries above cannot see them.
        val claimed = filterClaimed(inputKeys) + inputKeys.duplicates()
        inputs.firstOrNull { it.publicKey in claimed }?.let {
            return CoinageRegistrationError.InputAlreadyClaimed(it.input)
        }

        return null
    }

    suspend fun preCommitHandoff(assets: List<OwnAsset>): Result<CoinageHandoffCommit> {
        val marks = runCatching {
            assets.map { LedgerAsset(it.kind(), it, it.publicKey()) }
        }.getOrElse {
            logRejected(it)

            return Result.failure(it)
        }

        val keys = marks.map { it.publicKey }

        return repository.markHandedOff(marks) {
            // The mirror of Blocked handoff: an asset a transaction of ours still has a claim on cannot also
            // leave the device, or the peer and that transaction would both be spending it.
            val claimed = filterClaimed(keys)
            marks.firstOrNull { it.publicKey in claimed }?.asset?.let {
                throw CoinageRegistrationError.HandoffOfClaimedAsset(it)
            }
        }
            .onSuccess { _ -> coinageLogI("handoff-marked assets=${marks.map { it.describe() }}") }
            .onFailure(::logRejected)
            .map { RepositoryHandoffCommit(repository, keys) }
    }

    private suspend fun CoinageInput.publicKey(): AssetPublicKey = when (this) {
        is CoinageInput.Coin.Own -> coinKeypairDerivation.getDerivedAccountId(derivationIndex)
        is CoinageInput.Coin.Received -> publicKey
        is CoinageInput.Voucher -> voucherRingDerivation.memberKeyOf(ringVrfIndex)
    }

    private suspend fun OwnAsset.publicKey(): AssetPublicKey = when (this) {
        is OwnAsset.Coin -> coinKeypairDerivation.getDerivedAccountId(derivationIndex)
        is OwnAsset.Voucher -> voucherRingDerivation.memberKeyOf(ringVrfIndex)
    }

    private fun logRejected(error: Throwable) {
        coinageLogW("registration-rejected reason=${error::class.simpleName} detail=${error.message}")
    }
}

private class RepositoryHandoffCommit(
    private val repository: CoinageEntryRepository,
    private val keys: List<AssetPublicKey>,
) : CoinageHandoffCommit {
    override suspend fun commit(): Result<Unit> = repository.commitHandoffs(keys)
        .onSuccess { _ -> coinageLogI("handoff-committed keys=${keys.map { it.shortKey() }}") }
        .onFailure { error -> coinageLogW("handoff-commit-failed keys=${keys.map { it.shortKey() }} error=$error") }
}

private fun EntryRegistration.describe(id: CoinageTransactionId): String =
    "${coinageLogId(id, txHash, groupId)} checkpoint=${checkpoint.blockNumber} mortality=$mortalityBlocks " +
        "window=${checkpoint.blockNumber}..${checkpoint.blockNumber + mortalityBlocks} " +
        "inputs=${inputs.map { "${it.input}@${it.publicKey.shortKey()}" }} " +
        "outputs=${outputs.map { "${it.output}@${it.publicKey.shortKey()}" }}"

private fun LedgerAsset.describe(): String = "${asset ?: kind}@${publicKey.shortKey()}"

private fun List<AssetPublicKey>.duplicates(): Set<AssetPublicKey> =
    groupingBy { it }.eachCount().filterValues { it > 1 }.keys

private fun OwnAsset.kind() = when (this) {
    is OwnAsset.Coin -> CoinageAssetKind.COIN
    is OwnAsset.Voucher -> CoinageAssetKind.VOUCHER
}

/** The runtime enforces this era, so it is the only window an entry may be recovered against. */
private fun SendableExtrinsic.mortalEra(): Era.Mortal? =
    extrinsic.findExplicitOrNull(DefaultSignedExtensions.CHECK_MORTALITY) as? Era.Mortal
