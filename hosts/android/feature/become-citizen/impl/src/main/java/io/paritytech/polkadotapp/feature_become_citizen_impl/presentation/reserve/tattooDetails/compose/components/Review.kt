package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.compose.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.common.presentation.formatters.time.LocalTimeFormatter
import io.paritytech.polkadotapp.common.presentation.formatters.time.TimeFormatter
import io.paritytech.polkadotapp.common.presentation.formatters.time.formatBigPeriodDescriptive
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_impl.R
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.models.EvidenceReviewUiModel
import kotlin.time.Duration.Companion.days
import kotlin.time.Duration.Companion.minutes
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun Review(review: EvidenceReviewUiModel) {
    SpecificationsColumn(
        title = stringResource(RCommon.string.become_citizen_tattoo_details_evidence_review_title)
    ) {
        PolkadotSurface(
            modifier = Modifier.fillMaxWidth(),
            color = Color(0x0FFFFFFF),
            shape = PolkadotTheme.shapes.mediumIncreased
        ) {
            Row(
                modifier = Modifier.padding(PolkadotTheme.spacings.mediumIncreased),
                horizontalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.mediumIncreased),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Image(
                    modifier = Modifier.size(64.dp),
                    painter = painterResource(R.drawable.img_clock),
                    contentDescription = "tattoo_machine_image"
                )

                NovaText(
                    text = stringResource(
                        RCommon.string.become_citizen_tattoo_details_evidence_review_description,
                        LocalTimeFormatter.current.formatBigPeriodDescriptive(review.from),
                        LocalTimeFormatter.current.formatBigPeriodDescriptive(review.to)
                    ),
                    style = PolkadotTheme.typography.body.large,
                    color = PolkadotTheme.colors.fg.primary
                )
            }
        }
    }
}

@Preview
@Composable
private fun ReviewPreview() {
    PolkadotTheme {
        CompositionLocalProvider(
            LocalTimeFormatter provides TimeFormatter.mocked(LocalContext.current)
        ) {
            Review(
                EvidenceReviewUiModel(
                    from = 1.minutes,
                    to = 5.days
                )
            )
        }
    }
}
