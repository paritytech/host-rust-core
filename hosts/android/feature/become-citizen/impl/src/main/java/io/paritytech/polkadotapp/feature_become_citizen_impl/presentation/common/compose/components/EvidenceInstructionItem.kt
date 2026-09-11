package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.compose.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.layout
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.models.EvidenceInstructionItem

@Composable
fun EvidenceInstructionItemBlock(
    orderNumber: Int,
    item: EvidenceInstructionItem
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = PolkadotTheme.spacings.mediumIncreased),
        horizontalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.mediumIncreased)
    ) {
        NovaText(
            modifier = Modifier
                .background(PolkadotTheme.colors.bg.surface.nested, PolkadotTheme.shapes.extraSmall)
                .padding(PolkadotTheme.spacings.extraTiny)
                .matchHeightConstraintFirst(),
            text = orderNumber.toString(),
            textAlign = TextAlign.Center,
            style = PolkadotTheme.typography.title.medium,
            color = PolkadotTheme.colors.fg.secondary
        )

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.small)
        ) {
            NovaText(
                text = stringResource(item.titleRes),
                style = PolkadotTheme.typography.title.medium,
                color = PolkadotTheme.colors.fg.primary
            )

            NovaText(
                text = stringResource(item.descriptionRes),
                style = PolkadotTheme.typography.body.large,
                color = PolkadotTheme.colors.fg.secondary
            )
        }
    }
}

private fun Modifier.matchHeightConstraintFirst() = layout { measurable, constraints ->
    val placeable = measurable.measure(constraints)
    val width = maxOf(placeable.width, placeable.height)

    layout(width, placeable.height) {
        placeable.placeRelative(
            x = (width - placeable.width) / 2,
            y = 0
        )
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF000000)
@Composable
private fun EvidenceInstructionItemBlockPreview() {
    PolkadotTheme {
        EvidenceInstructionItemBlock(
            orderNumber = 1,
            item = EvidenceInstructionItem(
                titleRes = 1,
                descriptionRes = 2
            )
        )
    }
}
