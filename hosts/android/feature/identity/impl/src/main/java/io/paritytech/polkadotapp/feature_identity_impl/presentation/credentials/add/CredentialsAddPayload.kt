package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.add

import android.os.Parcelable
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialPlatform
import kotlinx.parcelize.Parcelize

@Parcelize
class CredentialsAddPayload(val platform: IdentityCredentialPlatform) : Parcelable
