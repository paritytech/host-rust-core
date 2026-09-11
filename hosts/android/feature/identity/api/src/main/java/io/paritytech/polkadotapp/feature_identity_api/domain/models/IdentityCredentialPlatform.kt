package io.paritytech.polkadotapp.feature_identity_api.domain.models

import android.os.Parcelable
import kotlinx.parcelize.Parcelize
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Parcelize
@Serializable
sealed interface IdentityCredentialPlatform : Parcelable {
    val username: String?

    @Parcelize
    @Serializable
    @SerialName(TWITTER)
    data class Twitter(override val username: String?) : IdentityCredentialPlatform, Parcelable

    @Parcelize
    @Serializable
    @SerialName(GITHUB)
    data class Github(override val username: String?) : IdentityCredentialPlatform, Parcelable

    @Parcelize
    @Serializable
    @SerialName(DISCORD)
    data class Discord(@SerialName("display_and_tag") override val username: String?) : IdentityCredentialPlatform, Parcelable

    companion object {
        const val TWITTER = "Twitter"
        const val GITHUB = "Github"
        const val DISCORD = "Discord"

        fun fromValue(value: String, username: String?) = when (value) {
            TWITTER -> Twitter(username)
            GITHUB -> Github(username)
            DISCORD -> Discord(username)
            else -> null
        }

        fun platformNames(): List<String> = listOf(TWITTER, GITHUB, DISCORD)

        fun IdentityCredentialPlatform.platformName() = when (this) {
            is Twitter -> TWITTER
            is Github -> GITHUB
            is Discord -> DISCORD
        }

        fun IdentityCredentialPlatform.baseUrl() = when (this) {
            is Twitter -> "x.com/$username"
            is Github -> "github.com/$username"
            is Discord -> "discord.com/$username"
        }
    }
}
