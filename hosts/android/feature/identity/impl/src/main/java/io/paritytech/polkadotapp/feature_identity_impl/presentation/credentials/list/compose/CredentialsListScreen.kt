package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.list.compose

import androidx.compose.foundation.layout.*
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.util.fastForEachIndexed
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.components.topbar.PolkadotTopBar
import io.paritytech.polkadotapp.design.components.topbar.TopBarTitleSize
import io.paritytech.polkadotapp.design.components.topbar.rememberTopBarAction
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialPlatform
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialState
import io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.list.CredentialsListContract
import io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.list.compose.components.CredentialItem
import io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.list.models.CredentialUiModel
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.toImmutableList
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun CredentialsListScreen(contract: CredentialsListContract) {
    val credentials by contract.credentials.collectAsStateWithLifecycle()

    CredentialsListScreenInternal(
        onBackAction = contract::backClicked,
        onSelectItemAction = contract::selectItem,
        credentials = credentials.toImmutableList()
    )
}

@Composable
private fun CredentialsListScreenInternal(
    onBackAction: () -> Unit,
    onSelectItemAction: (CredentialUiModel) -> Unit,
    credentials: ImmutableList<CredentialUiModel>
) {
    PolkadotSurface {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .systemBarsPadding()
        ) {
            PolkadotTopBar(
                title = stringResource(RCommon.string.identity_credentials_platforms_title),
                navigationAction = rememberTopBarAction(onBackAction),
                titleSize = TopBarTitleSize.Large,
            )

            VerticalSpacer { small }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = PolkadotTheme.spacings.large)
            ) {
                NovaText(
                    text = stringResource(RCommon.string.identity_credentials_platforms_description),
                    style = PolkadotTheme.typography.body.large,
                    color = PolkadotTheme.colors.fg.secondary
                )

                VerticalSpacer { large }

                PolkadotSurface(
                    modifier = Modifier.fillMaxWidth(),
                    color = PolkadotTheme.colors.bg.surface.container,
                    shape = PolkadotTheme.shapes.mediumIncreased
                ) {
                    Column {
                        credentials.fastForEachIndexed { index, model ->
                            CredentialItem(
                                item = model,
                                onItemAction = onSelectItemAction
                            )

                            if (index < credentials.lastIndex) {
                                CredentialDivider()
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CredentialDivider() {
    HorizontalDivider(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = PolkadotTheme.spacings.mediumIncreased),
        color = PolkadotTheme.colors.stroke.primary
    )
}

@Preview
@Composable
private fun CredentialsListScreenPreview() {
    PolkadotTheme {
        CredentialsListScreenInternal(
            onBackAction = {},
            onSelectItemAction = {},
            credentials = persistentListOf(
                CredentialUiModel(
                    IdentityCredentialPlatform.Github(""),
                    IdentityCredentialState.NotAdded
                ),
                CredentialUiModel(
                    IdentityCredentialPlatform.Discord(""),
                    IdentityCredentialState.Rejected
                ),
                CredentialUiModel(
                    IdentityCredentialPlatform.Twitter(""),
                    IdentityCredentialState.Review
                ),
                CredentialUiModel(
                    IdentityCredentialPlatform.Discord("aRolf"),
                    IdentityCredentialState.Confirmed("@aRolf")
                )
            )
        )
    }
}
