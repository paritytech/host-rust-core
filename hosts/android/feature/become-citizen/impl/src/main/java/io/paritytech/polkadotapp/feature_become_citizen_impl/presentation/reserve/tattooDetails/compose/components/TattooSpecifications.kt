package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.compose.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.tooling.preview.Preview
import io.paritytech.polkadotapp.common.presentation.formatters.time.LocalTimeFormatter
import io.paritytech.polkadotapp.common.presentation.formatters.time.TimeFormatter
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.models.TattooSizeUiModel
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.models.EvidenceReviewUiModel
import kotlin.time.Duration.Companion.days
import kotlin.time.Duration.Companion.minutes

@Composable
fun TattooSpecifications(
    size: TattooSizeUiModel,
    review: EvidenceReviewUiModel?
) {
    PolkadotSurface(
        modifier = Modifier.fillMaxWidth(),
        color = PolkadotTheme.colors.bg.surface.container,
        shape = PolkadotTheme.shapes.extraLarge
    ) {
        Column(
            modifier = Modifier.padding(
                vertical = PolkadotTheme.spacings.large,
                horizontal = PolkadotTheme.spacings.mediumIncreased
            ),
            verticalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.large)
        ) {
            Size(size)
            HorizontalDivider()
            Location()
            HorizontalDivider()
            Execution()
            HorizontalDivider()
            Evidence()
            review?.let {
                HorizontalDivider()
                Review(it)
            }
        }
    }
}

@Preview(device = "spec:width=1080px,height=10000px,dpi=440")
@Composable
private fun TattooSpecsPreview() {
    PolkadotTheme {
        CompositionLocalProvider(
            LocalTimeFormatter provides TimeFormatter.mocked(LocalContext.current)
        ) {
            TattooSpecifications(
                size = TattooSizeUiModel.Variable(10, 20),
                review = EvidenceReviewUiModel(
                    from = 1.minutes,
                    to = 5.days
                )
            )
        }
    }
}
