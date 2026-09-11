package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.compose

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.CancelFilled
import io.paritytech.polkadotapp.design.components.icon.vectors.CheckCircleFilled
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.model.VotingOption

@Composable
internal fun VotingButtons(
    modifier: Modifier = Modifier,
    onVote: (VotingOption) -> Unit
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.small)
    ) {
        VotingButton(
            icon = NovaIcons.CancelFilled,
            textRes = R.string.common_false,
            contentColor = PolkadotTheme.colors.fg.error,
            onClick = { onVote(VotingOption.FALSE) },
            modifier = Modifier.weight(1f)
        )

        VotingButton(
            icon = NovaIcons.CheckCircleFilled,
            textRes = R.string.common_true,
            contentColor = PolkadotTheme.colors.fg.success,
            onClick = { onVote(VotingOption.TRUE) },
            modifier = Modifier.weight(1f)
        )
    }
}
