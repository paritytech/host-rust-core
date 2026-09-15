package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.compose.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.common.utils.CurrencyConfig
import io.paritytech.polkadotapp.design.colors.LegacyNovaStableColors
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.progress.NovaCircularProgressIndicator
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.LocalTokenAmountFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.formatFiat
import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.TokenAmountModel
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.theme.NovaPrizesColors
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun WeeklyGameDepositBottomSheetContent(
    requiredAmount: TokenAmountModel,
    onDeposit: () -> Unit,
    inProgress: Boolean
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(NovaPrizesColors.bottomSheetBackground)
            .padding(PolkadotTheme.spacings.mediumIncreased)
    ) {
        val formattedAmount = LocalTokenAmountFormatter.current.formatFiat(requiredAmount)

        Column(
            modifier = Modifier.padding(PolkadotTheme.spacings.small)
        ) {
            NovaText(
                text = stringResource(RCommon.string.chat_bot_weekly_game_deposit_required_title).uppercase(),
                style = PolkadotTheme.typography.title.medium,
                color = NovaPrizesColors.textSecondary
            )

            VerticalSpacer { small }

            NovaText(
                text = stringResource(
                    RCommon.string.chat_bot_weekly_game_deposit_required_subtitle,
                    formattedAmount
                ),
                style = PolkadotTheme.typography.headline.small,
                color = NovaPrizesColors.textPrimary
            )

            VerticalSpacer { extraMedium }

            NovaText(
                text = stringResource(
                    RCommon.string.chat_bot_weekly_game_deposit_required_description,
                    CurrencyConfig.symbol
                ),
                style = PolkadotTheme.typography.body.large,
                color = NovaPrizesColors.textSecondary
            )
        }

        VerticalSpacer { mediumIncreased }

        AnimatedVisibility(
            visible = inProgress
        ) {
            Row(
                modifier = Modifier.padding(PolkadotTheme.spacings.tiny),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.tiny)
            ) {
                NovaCircularProgressIndicator(
                    modifier = Modifier.size(16.dp),
                    strokeWidth = 1.dp,
                    color = LegacyNovaStableColors.AmberAmber500
                )

                NovaText(
                    text = stringResource(RCommon.string.chat_bot_weekly_game_deposit_required_funding),
                    style = PolkadotTheme.typography.body.medium,
                    color = LegacyNovaStableColors.AmberAmber500
                )
            }
        }

        PolkadotTextButton(
            modifier = Modifier.fillMaxWidth(),
            text = stringResource(RCommon.string.chat_bot_weekly_game_deposit_required_action, formattedAmount),
            enabled = inProgress.not(),
            onClick = onDeposit
        )
    }
}
