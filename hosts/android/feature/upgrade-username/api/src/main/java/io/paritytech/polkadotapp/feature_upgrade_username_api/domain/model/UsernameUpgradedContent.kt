package io.paritytech.polkadotapp.feature_upgrade_username_api.domain.model

import kotlinx.serialization.Serializable

@Serializable
data class UsernameUpgradedContent(
    val username: String,
    val usernameWithoutSuffix: String
)
