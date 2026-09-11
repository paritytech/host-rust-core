package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.add.compose.components

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialPlatform

@Composable
fun IdentityCredentialPlatform.getPlatformName() = stringResource(
    when (this) {
        is IdentityCredentialPlatform.Discord -> R.string.platform_discord
        is IdentityCredentialPlatform.Twitter -> R.string.platform_twitter
        is IdentityCredentialPlatform.Github -> R.string.platform_github
    }
)

fun IdentityCredentialPlatform.getSettingsUrl(username: String) = when (this) {
    is IdentityCredentialPlatform.Discord -> null
    is IdentityCredentialPlatform.Twitter -> "https://x.com/settings/profile"
    is IdentityCredentialPlatform.Github -> "https://github.com/$username"
}
