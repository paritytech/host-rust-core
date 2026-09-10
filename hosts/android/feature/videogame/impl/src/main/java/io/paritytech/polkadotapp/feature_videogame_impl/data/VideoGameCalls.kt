package io.paritytech.polkadotapp.feature_videogame_impl.data

import io.novasama.substrate_sdk_android.runtime.definitions.types.generics.MultiSignature
import io.novasama.substrate_sdk_android.runtime.definitions.types.generics.prepareForEncoding
import io.novasama.substrate_sdk_android.runtime.extrinsic.builder.ExtrinsicBuilder
import io.novasama.substrate_sdk_android.runtime.extrinsic.call
import io.paritytech.polkadotapp.chains.util.Modules
import io.paritytech.polkadotapp.chains.util.scaleEncodeSerializable
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_videogame_impl.data.airdrop.AirdropVrf
import io.paritytech.polkadotapp.feature_videogame_impl.data.extension.GameAsInvitedExtension
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.FullVideoGameReport

@JvmInline
value class VideoGameCalls(val extrinsicBuilder: ExtrinsicBuilder)

val ExtrinsicBuilder.videoGame: VideoGameCalls
    get() = VideoGameCalls(this)

fun VideoGameCalls.signUpWithAccount(key: ByteArray, airdrop: AirdropVrf?) {
    extrinsicBuilder.call(
        moduleName = Modules.VIDEO_GAME,
        callName = "sign_up_with_account",
        arguments = mapOf(
            "identifier_key" to key,
            "airdrop" to airdrop?.scaleEncodeSerializable(),
        )
    )
}

fun VideoGameCalls.signUpWithAlias(
    statementAccountId: AccountId,
    signature: MultiSignature,
    airdrop: AirdropVrf?,
) {
    extrinsicBuilder.call(
        moduleName = Modules.VIDEO_GAME,
        callName = "sign_up_with_alias",
        arguments = mapOf(
            "statement_account" to statementAccountId.value,
            "sig" to signature.prepareForEncoding(),
            "airdrop" to airdrop?.scaleEncodeSerializable(),
        )
    )
}

fun VideoGameCalls.signUpWithInvitation(
    identifierKey: ByteArray,
    inviter: AccountId,
    ticket: AccountId,
    signature: MultiSignature,
    airdrop: AirdropVrf?,
) {
    extrinsicBuilder.call(
        moduleName = Modules.VIDEO_GAME,
        callName = "sign_up_with_invite",
        arguments = mapOf(
            "identifier_key" to identifierKey,
            "airdrop" to airdrop?.scaleEncodeSerializable(),
        )
    )

    val extension = GameAsInvitedExtension(inviter, ticket, signature)
    extrinsicBuilder.setTransactionExtension(extension)
}

fun VideoGameCalls.claimAirdrop(gameIndex: Int, beneficiary: AccountId) {
    extrinsicBuilder.call(
        moduleName = Modules.VIDEO_GAME,
        callName = "claim_airdrop",
        arguments = mapOf(
            "game_index" to gameIndex.toBigInteger(),
            "beneficiary" to beneficiary.value,
        )
    )
}

fun VideoGameCalls.offboard() {
    extrinsicBuilder.call(
        moduleName = Modules.VIDEO_GAME,
        callName = "offboard",
        arguments = emptyMap()
    )
}

fun VideoGameCalls.report(fullReport: FullVideoGameReport) {
    extrinsicBuilder.call(
        moduleName = Modules.VIDEO_GAME,
        callName = "report",
        arguments = mapOf(
            "full_report" to fullReport.scaleEncodeSerializable()
        )
    )
}
