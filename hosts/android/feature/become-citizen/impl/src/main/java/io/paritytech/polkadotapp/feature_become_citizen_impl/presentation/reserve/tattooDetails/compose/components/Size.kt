package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.compose.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.models.TattooSizeUiModel
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
internal fun Size(size: TattooSizeUiModel) {
    SpecificationsColumn(
        title = stringResource(RCommon.string.become_citizen_tattoo_size_title)
    ) {
        when (size) {
            is TattooSizeUiModel.Fixed -> {
                NovaText(
                    text = "${size.size}x${size.size}",
                    style = PolkadotTheme.typography.headline.large,
                    color = PolkadotTheme.colors.fg.primary
                )
            }

            is TattooSizeUiModel.Variable -> {
                Row {
                    val weightModifier = Modifier.weight(1f)
                    SizeOption(
                        modifier = weightModifier,
                        title = stringResource(RCommon.string.common_from),
                        size = size.from
                    )
                    SizeOption(
                        modifier = weightModifier,
                        title = stringResource(RCommon.string.common_to),
                        size = size.to
                    )
                }

                VerticalSpacer { large }

                NovaText(
                    text = stringResource(RCommon.string.become_citizen_tattoo_size_description, size.from, size.to),
                    style = PolkadotTheme.typography.body.large,
                    color = PolkadotTheme.colors.fg.primary
                )
            }
        }
    }
}

@Composable
private fun SizeOption(modifier: Modifier, title: String, size: Int) {
    Column(modifier) {
        NovaText(
            text = title,
            style = PolkadotTheme.typography.body.medium,
            color = PolkadotTheme.colors.fg.tertiary
        )
        NovaText(
            text = "${size}x$size",
            style = PolkadotTheme.typography.headline.large,
            color = PolkadotTheme.colors.fg.primary
        )
    }
}

@Preview
@Composable
private fun SizePreview() {
    PolkadotTheme {
        Size(size = TattooSizeUiModel.Variable(20, 50))
    }
}
