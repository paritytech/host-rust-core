package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.list.models

import androidx.compose.runtime.Immutable
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialPlatform
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialState

@Immutable
data class CredentialUiModel(
    val platform: IdentityCredentialPlatform,
    val state: IdentityCredentialState
)
