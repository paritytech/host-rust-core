package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.Close
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.components.topbar.PolkadotTopBar
import io.paritytech.polkadotapp.design.components.topbar.TopBarTitleAlignment
import io.paritytech.polkadotapp.design.components.topbar.rememberTopBarAction
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.compose.components.EvidenceInstructionItemBlock
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.models.EvidenceInstructionItem
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf

@Composable
fun EvidenceInstructionScreen(
    onClose: () -> Unit,
    icon: ImageVector,
    title: String,
    items: ImmutableList<EvidenceInstructionItem>,
    actionText: String,
    onActionClick: () -> Unit
) {
    PolkadotSurface(
        modifier = Modifier.fillMaxSize()
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
        ) {
            PolkadotTopBar(
                navigationAction = rememberTopBarAction(
                    action = onClose,
                    icon = NovaIcons.Close
                ),
                titleAlignment = TopBarTitleAlignment.Center,
            )

            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
                contentPadding = PaddingValues(
                    vertical = PolkadotTheme.spacings.mediumIncreased,
                    horizontal = PolkadotTheme.spacings.extraLarge
                )
            ) {
                item {
                    Header(
                        icon = icon,
                        title = title
                    )

                    VerticalSpacer { large }
                }

                itemsIndexed(items) { index, item ->
                    EvidenceInstructionItemBlock(index + 1, item)

                    if (index < items.lastIndex) {
                        HorizontalDivider()
                    }
                }
            }

            ActionFooter(
                actionText = actionText,
                onActionClick = onActionClick
            )
        }
    }
}

@Composable
private fun Header(icon: ImageVector, title: String) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        PolkadotSurface(
            shape = RoundedCornerShape(40.dp),
            color = Color(0x2EFFFFFF)
        ) {
            NovaIcon(
                modifier = Modifier
                    .padding(PolkadotTheme.spacings.large)
                    .size(48.dp),
                imageVector = icon,
            )
        }

        VerticalSpacer { extraLarge }

        NovaText(
            text = title,
            style = PolkadotTheme.typography.headline.small,
            color = PolkadotTheme.colors.fg.primary,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun ActionFooter(
    actionText: String,
    onActionClick: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(PolkadotTheme.colors.bg.surface.container)
            .navigationBarsPadding()
    ) {
        PolkadotTextButton(
            modifier = Modifier
                .fillMaxWidth()
                .padding(PolkadotTheme.spacings.large),
            text = actionText,
            onClick = onActionClick,
        )
    }
}

@Preview
@Composable
private fun EvidenceInstructionScreenPreview() {
    PolkadotTheme {
        EvidenceInstructionScreen(
            onClose = {},
            icon = NovaIcons.Close,
            title = "Video Recording Instructions",
            items = persistentListOf(
                EvidenceInstructionItem(
                    titleRes = 1,
                    descriptionRes = 21
                ),
                EvidenceInstructionItem(
                    titleRes = 4,
                    descriptionRes = 5
                ),
                EvidenceInstructionItem(
                    titleRes = 32,
                    descriptionRes = 321
                )
            ),
            actionText = "Start Recording",
            onActionClick = {}
        )
    }
}
