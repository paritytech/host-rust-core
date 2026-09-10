package io.paritytech.polkadotapp.feature_people_impl.data.signer.origins.extension

import io.novasama.substrate_sdk_android.runtime.definitions.types.composite.DictEnum
import io.novasama.substrate_sdk_android.runtime.extrinsic.Nonce
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchProof
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchSignature
import io.paritytech.polkadotapp.feature_members_api.data.model.RingIndex
import io.paritytech.polkadotapp.feature_members_api.data.model.RingRevision
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId

sealed class AsPersonInfo {
    class AsPersonalAliasWithAccount(val nonce: Nonce) : AsPersonInfo()

    class AsPersonalAliasWithProof(
        val proof: BandersnatchProof,
        val context: BandersnatchContext,
        val ringIndex: RingIndex,
        val revision: RingRevision
    ) : AsPersonInfo()

    class AsPersonalIdentityWithProof(val signature: BandersnatchSignature, val personId: PersonId) : AsPersonInfo()

    class AsPersonalIdentityWithAccount(val nonce: Nonce) : AsPersonInfo()
}

fun AsPersonInfo.toEncodableInstance(): DictEnum.Entry<*> {
    return when (this) {
        is AsPersonInfo.AsPersonalAliasWithAccount -> DictEnum.Entry(
            name = "AsPersonalAliasWithAccount",
            value = nonce
        )

        is AsPersonInfo.AsPersonalAliasWithProof -> DictEnum.Entry(
            name = "AsPersonalAliasWithProof",
            value = listOf(proof.value, ringIndex.value, revision.value.toBigInteger(), context.value)
        )

        is AsPersonInfo.AsPersonalIdentityWithProof -> DictEnum.Entry(
            name = "AsPersonalIdentityWithProof",
            value = listOf(signature.value, personId.id)
        )

        is AsPersonInfo.AsPersonalIdentityWithAccount -> DictEnum.Entry(
            name = "AsPersonalIdentityWithAccount",
            value = nonce
        )
    }
}
