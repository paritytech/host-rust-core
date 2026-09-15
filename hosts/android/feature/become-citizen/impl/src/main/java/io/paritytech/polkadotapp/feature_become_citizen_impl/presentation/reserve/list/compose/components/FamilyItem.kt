package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.list.compose.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.tooling.preview.Preview
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImage
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.models.TattooFamilyUiIdentifier
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.list.models.TattooFamilyUiModel
import kotlinx.collections.immutable.toImmutableList
import java.math.BigInteger
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
internal fun FamilyItem(
    modifier: Modifier = Modifier,
    familyModel: TattooFamilyUiModel,
    canNavigate: Boolean
) {
    Column(
        modifier = modifier
    ) {
        Row(
            modifier = Modifier.padding(
                start = PolkadotTheme.spacings.large,
                end = PolkadotTheme.spacings.mediumIncreased
            ),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.mediumIncreased)
        ) {
            Column(
                modifier = Modifier.weight(1f)
            ) {
                NovaText(
                    text = pluralStringResource(RCommon.plurals.tattoo_family_designs, familyModel.totalCount, familyModel.totalCount),
                    style = PolkadotTheme.typography.body.small,
                    color = PolkadotTheme.colors.fg.secondary
                )

                NovaText(
                    text = familyModel.name,
                    style = PolkadotTheme.typography.headline.small,
                    color = PolkadotTheme.colors.fg.primary
                )
            }

            FamilyItemIcon(canNavigate)
        }

        VerticalSpacer { extraMedium }

        if (familyModel.exampleTattoos.isNotEmpty()) {
            TattoosCollage(tattoos = familyModel.exampleTattoos)
        }
    }
}

@Preview
@Composable
private fun FamilyItemPreview() {
    PolkadotTheme {
        PolkadotSurface {
            FamilyItem(
                familyModel = TattooFamilyUiModel(
                    identifier = TattooFamilyUiIdentifier.Single(BigInteger.valueOf(1)),
                    name = "Test family",
                    totalCount = 12,
                    exampleTattoos = List(3) { TattooImage.Empty }.toImmutableList()
                ),
                canNavigate = false
            )
        }
    }
}
