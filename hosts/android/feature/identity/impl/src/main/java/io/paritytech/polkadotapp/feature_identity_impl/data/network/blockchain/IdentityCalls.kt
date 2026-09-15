package io.paritytech.polkadotapp.feature_identity_impl.data.network.blockchain

import io.novasama.substrate_sdk_android.encrypt.SignatureWrapper
import io.novasama.substrate_sdk_android.runtime.definitions.types.composite.DictEnum
import io.novasama.substrate_sdk_android.runtime.definitions.types.composite.Struct
import io.novasama.substrate_sdk_android.runtime.definitions.types.instances.SignatureInstanceConstructor
import io.novasama.substrate_sdk_android.runtime.extrinsic.builder.ExtrinsicBuilder
import io.novasama.substrate_sdk_android.runtime.extrinsic.call
import io.paritytech.polkadotapp.chains.util.Modules
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialPlatform
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialPlatform.Companion.platformName

@JvmInline
value class IdentityCalls(val extrinsicBuilder: ExtrinsicBuilder)

val ExtrinsicBuilder.identity: IdentityCalls
    get() = IdentityCalls(this)

fun IdentityCalls.setPersonalIdentity(accountId: AccountId, signatureWrapper: SignatureWrapper, username: ByteArray) {
    extrinsicBuilder.call(
        moduleName = Modules.IDENTITY,
        callName = "set_personal_identity",
        arguments = mapOf(
            "account" to accountId.value,
            "signature" to SignatureInstanceConstructor.constructInstance(extrinsicBuilder.runtime.typeRegistry, signatureWrapper),
            "username" to username
        )
    )
}

fun IdentityCalls.submitPersonalCredentialEvidence(
    platform: IdentityCredentialPlatform,
    credential: String
) {
    extrinsicBuilder.call(
        moduleName = Modules.IDENTITY,
        callName = "submit_personal_credential_evidence",
        arguments = mapOf(
            "credential" to DictEnum.Entry(
                name = platform.platformName(),
                value = Struct.Instance(
                    mapOf(platform.getCredentialFieldName() to credential.encodeToByteArray())
                )
            )
        )
    )
}

private fun IdentityCredentialPlatform.getCredentialFieldName() = when (this) {
    is IdentityCredentialPlatform.Discord -> "display_and_tag"
    is IdentityCredentialPlatform.Twitter, is IdentityCredentialPlatform.Github -> "username"
}
