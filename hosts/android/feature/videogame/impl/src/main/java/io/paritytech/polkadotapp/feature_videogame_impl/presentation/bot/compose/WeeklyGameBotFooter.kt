package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.compose

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.res.stringResource
import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonColors
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonStyle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.placeholder.DimSwitchPlaceholder
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_upgrade_username_api.presentation.bot.UpgradeUsernameWidget
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.compose.components.UpcomingGameWidget
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.models.FooterUiState
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.models.UpcomingGameUiState
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.models.WeeklyGameFooterState
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.theme.NovaPrizesColors
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
internal fun WeeklyGameBotFooter(
    footerContent: WeeklyGameFooterState,
    uiState: FooterUiState,
    onRegister: () -> Unit,
    onStartPlaying: () -> Unit,
    onUpgradeUsernameClick: () -> Unit,
    onAddToCalendar: () -> Unit,
    onEditClick: () -> Unit,
    pillSlot: @Composable () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .animateContentSize()
    ) {
        val upgradeUsernameUiState = uiState.upgradeUsernameUiState
        if (upgradeUsernameUiState != null) {
            val maxWidthModifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = PolkadotTheme.spacings.mediumIncreased)

            if (!upgradeUsernameUiState.isUpgraded) {
                UpgradeUsernameWidget(
                    modifier = maxWidthModifier,
                    usernameWithoutSuffix = upgradeUsernameUiState.fullName,
                    isUpgraded = false
                )

                VerticalSpacer { extraSmall }

                PolkadotTextButton(
                    modifier = maxWidthModifier,
                    text = stringResource(R.string.upgrade_username_CTA),
                    style = upgradeUsernameCtaStyle(),
                    onClick = onUpgradeUsernameClick
                )

                VerticalSpacer { small }
            }
        }

        when (footerContent) {
            WeeklyGameFooterState.Loading -> Unit
            WeeklyGameFooterState.Normal -> {
                val upcoming = uiState.upcomingGameUiState?.takeUnless { it is UpcomingGameUiState.Starting }
                upcoming?.let {
                    VerticalSpacer { small }

                    UpcomingGameWidget(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = PolkadotTheme.spacings.mediumIncreased),
                        upcomingGame = it,
                        onRegister = onRegister,
                        onStartPlaying = onStartPlaying,
                        onAddToCalendar = onAddToCalendar
                    )
                }
            }

            WeeklyGameFooterState.OtherDimCommitted -> {
                if (upgradeUsernameUiState == null) {
                    DimSwitchPlaceholder(
                        text = stringResource(RCommon.string.dim_switch_to_dim1_placeholder),
                        buttonText = stringResource(RCommon.string.common_edit),
                        onEditClick = onEditClick
                    )
                }
            }
        }

        pillSlot()
    }
}

@Composable
private fun upgradeUsernameCtaStyle(): PolkadotButtonStyle {
    val background = NovaPrizesColors.upgradeUsernameCtaBackground
    val content = NovaPrizesColors.upgradeUsernameCtaContent
    return remember(background, content) {
        val brush = SolidColor(background)
        object : PolkadotButtonStyle {
            override val colors = PolkadotButtonColors(
                containerBrush = brush,
                contentColor = content,
                disabledContainerBrush = brush,
                disabledContentColor = content,
            )
            override val rippleColor = content
        }
    }
}
