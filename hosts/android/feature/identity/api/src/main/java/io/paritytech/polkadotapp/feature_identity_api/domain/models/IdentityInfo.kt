package io.paritytech.polkadotapp.feature_identity_api.domain.models

class IdentityInfo(
    val platform: IdentityCredentialPlatform,
    val credential: String?
)
