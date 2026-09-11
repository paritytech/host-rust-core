package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.rejected

import android.os.Parcelable
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialPlatform
import kotlinx.parcelize.Parcelize

@Parcelize
data class CredentialsRejectedPayload(
    val platform: IdentityCredentialPlatform
) : Parcelable
