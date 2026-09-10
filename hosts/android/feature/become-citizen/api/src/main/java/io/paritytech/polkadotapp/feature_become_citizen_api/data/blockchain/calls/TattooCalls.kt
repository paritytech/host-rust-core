package io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.calls

import io.novasama.substrate_sdk_android.runtime.definitions.types.composite.DictEnum
import io.novasama.substrate_sdk_android.runtime.definitions.types.generics.MultiSignature
import io.novasama.substrate_sdk_android.runtime.definitions.types.generics.prepareForEncoding
import io.novasama.substrate_sdk_android.runtime.extrinsic.builder.ExtrinsicBuilder
import io.novasama.substrate_sdk_android.runtime.extrinsic.call
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchPublicKey
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchSignature
import io.paritytech.polkadotapp.chains.network.binding.tupleOf
import io.paritytech.polkadotapp.chains.util.EncodedArguments.Companion.autoEncodedArgs
import io.paritytech.polkadotapp.chains.util.Modules
import io.paritytech.polkadotapp.chains.util.call
import io.paritytech.polkadotapp.chains.util.scaleEncodeSerializable
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_account_api.domain.model.PersonPublicKey
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.ProceduralSeed
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooId
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models.ReferralTicketPublic
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import java.math.BigInteger

@JvmInline
value class ProofOfInkCalls(val extrinsicBuilder: ExtrinsicBuilder)

val ExtrinsicBuilder.proofOfInk: ProofOfInkCalls
    get() = ProofOfInkCalls(this)

// TODO we cannot yet replace this logic with a simple tattooId.scaleEncodeSerializable since
// ProceduralPersonal has personalId field that is not present in the InkChoice, so
// ProceduralPersonal should either have a custom serializer or we should split the models
// for InkChoice and InkSpec
fun ProofOfInkCalls.commit(tattooId: TattooId) {
    when (tattooId) {
        is TattooId.DesignedElective -> commitCall(
            choiceName = "DesignedElective",
            choiceValue = tupleOf(tattooId.familyIndex, tattooId.index.toBigInteger())
        )

        is TattooId.Procedural -> commitCall(
            choiceName = "Procedural",
            choiceValue = tupleOf(
                tattooId.familyIndex,
                when (val seed = tattooId.seed) {
                    is ProceduralSeed.Final -> error("Could not get index from final seed")
                    is ProceduralSeed.Raw -> seed.index.toBigInteger()
                }
            )
        )

        is TattooId.ProceduralAccount -> commitCall(
            choiceName = "ProceduralAccount",
            choiceValue = tattooId.familyIndex
        )

        is TattooId.ProceduralPersonal -> commitCall(
            choiceName = "ProceduralPersonal",
            choiceValue = tattooId.familyIndex,
            personId = tattooId.personId
        )
    }
}

fun ProofOfInkCalls.apply() {
    extrinsicBuilder.call(
        moduleName = Modules.PROOF_OF_INK,
        callName = "apply",
        arguments = emptyMap()
    )
}

fun ProofOfInkCalls.applyWithInvitation(
    inviter: AccountId,
    ticket: AccountId,
    signature: MultiSignature,
) {
    extrinsicBuilder.call(
        moduleName = Modules.PROOF_OF_INK,
        callName = "apply_with_invitation",
        arguments = mapOf(
            "inviter" to inviter.value,
            "ticket" to ticket.value,
            "signature" to signature.prepareForEncoding(),
        )
    )
}

fun ProofOfInkCalls.applyWithSignature(
    referrer: BigInteger,
    signature: MultiSignature,
    ticket: ReferralTicketPublic
) {
    extrinsicBuilder.call(
        moduleName = Modules.PROOF_OF_INK,
        callName = "apply_with_signature",
        arguments = mapOf(
            "referrer" to referrer,
            "signature" to signature.prepareForEncoding(),
            "ticket" to ticket.publicKey
        )
    )
}

fun ProofOfInkCalls.flakeout() {
    extrinsicBuilder.call(
        moduleName = Modules.PROOF_OF_INK,
        callName = "flakeout",
        arguments = emptyMap()
    )
}

fun ProofOfInkCalls.submitEvidenceHash(evidenceHash: ByteArray) {
    extrinsicBuilder.call(
        moduleName = Modules.PROOF_OF_INK,
        callName = "submit_evidence",
        arguments = mapOf("evidence" to evidenceHash)
    )
}

fun ProofOfInkCalls.allocateFull() {
    extrinsicBuilder.call(
        moduleName = Modules.PROOF_OF_INK,
        callName = "allocate_full",
        arguments = emptyMap()
    )
}

fun ProofOfInkCalls.registerNonReferred(
    key: PersonPublicKey,
    rewardDestination: AccountId,
    proofOfOwnership: BandersnatchSignature,
) {
    extrinsicBuilder.call(
        moduleName = Modules.PROOF_OF_INK,
        callName = "register_non_referred",
        arguments = autoEncodedArgs(
            "key" to key,
            "destination" to rewardDestination,
            "proof_of_ownership" to proofOfOwnership
        )
    )
}

fun ProofOfInkCalls.registerReferred(
    key: PersonPublicKey,
    rewardDestination: AccountId,
    proofOfOwnership: BandersnatchSignature,
) {
    extrinsicBuilder.call(
        moduleName = Modules.PROOF_OF_INK,
        callName = "register_referred",
        arguments = autoEncodedArgs(
            "key" to key,
            "destination" to rewardDestination,
            "proof_of_ownership" to proofOfOwnership
        )
    )
}

fun ProofOfInkCalls.setReferralTicket(ticket: ReferralTicketPublic) {
    extrinsicBuilder.call(
        moduleName = Modules.PROOF_OF_INK,
        callName = "set_referral_ticket",
        arguments = mapOf(
            "ticket" to ticket.publicKey
        )
    )
}

fun ProofOfInkCalls.cancelReferralTicket(ticket: ReferralTicketPublic) {
    extrinsicBuilder.call(
        moduleName = Modules.PROOF_OF_INK,
        callName = "cancel_referral_ticket",
        arguments = mapOf(
            "ticket" to ticket.publicKey
        )
    )
}

fun ProofOfInkCalls.registerSuccessfulReferralVoucher(bandersnatchPublicKey: BandersnatchPublicKey) {
    extrinsicBuilder.call(
        moduleName = Modules.PROOF_OF_INK,
        callName = "register_successful_referral_voucher",
        arguments = mapOf(
            "voucher_key" to bandersnatchPublicKey.scaleEncodeSerializable()
        )
    )
}

private fun ProofOfInkCalls.commitCall(
    choiceName: String,
    choiceValue: Any,
    personId: PersonId? = null
) {
    extrinsicBuilder.call(
        moduleName = Modules.PROOF_OF_INK,
        callName = "commit",
        arguments = mutableMapOf<String, Any>(
            "choice" to DictEnum.Entry(
                name = choiceName,
                value = choiceValue
            )
        ).apply {
            personId?.let { put("require_id", personId.id) }
        }
    )
}
