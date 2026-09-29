package io.paritytech.polkadotapp.feature_upgrade_username_impl.presentation.upgrade.compose

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonColors
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonStyle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.Close
import io.paritytech.polkadotapp.design.components.spacer.FillerSpacer
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.components.topbar.PolkadotTopBar
import io.paritytech.polkadotapp.design.components.topbar.TopBarTitleAlignment
import io.paritytech.polkadotapp.design.components.topbar.rememberTopBarAction
import io.paritytech.polkadotapp.design.theme.ForceDarkBackgroundSystemBarsEffect
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.designsystem.colors.BerlinNightPalette
import io.paritytech.polkadotapp.designsystem.colors.LocalPolkadotColors
import io.paritytech.polkadotapp.feature_upgrade_username_impl.presentation.upgrade.UpgradeUsernameContract
import io.paritytech.polkadotapp.feature_upgrade_username_impl.presentation.upgrade.UpgradeUsernameFieldState
import io.paritytech.polkadotapp.feature_upgrade_username_impl.presentation.upgrade.UpgradeUsernameUiState
import io.paritytech.polkadotapp.common.R as RCommon

private val FieldRadius = 12.dp
private val FieldHeight = 56.dp
private val FieldBorder = 1.5.dp

private val ErrorPillRadius = 8.dp

private val FieldTextStyle = TextStyle(
    fontSize = 18.sp,
    lineHeight = 22.sp,
    fontWeight = FontWeight.SemiBold,
)
private val TitleStyle = TextStyle(
    fontSize = 32.sp,
    lineHeight = 38.sp,
    fontWeight = FontWeight.SemiBold,
)
private val DescriptionStyle = TextStyle(
    fontSize = 16.sp,
    lineHeight = 20.sp,
    fontWeight = FontWeight.Normal,
)

private val ErrorPillTextStyle = TextStyle(
    fontSize = 12.sp,
    lineHeight = 18.sp,
    fontWeight = FontWeight.Normal,
)

@Composable
fun UpgradeUsernameScreen(contract: UpgradeUsernameContract) {
    val uiState by contract.uiState.collectAsStateWithLifecycle()

    ForceDarkBackgroundSystemBarsEffect()

    CompositionLocalProvider(LocalPolkadotColors provides remember { BerlinNightPalette() }) {
        UpgradeUsernameScreenInternal(
            state = uiState,
            onUsernameChanged = contract::onUsernameChanged,
            onClaimAction = contract::onClaimAction,
            onBackClick = contract::onBackClick
        )
    }
}

@Composable
private fun UpgradeUsernameScreenInternal(
    state: UpgradeUsernameUiState,
    onUsernameChanged: (String) -> Unit,
    onClaimAction: () -> Unit,
    onBackClick: () -> Unit,
) {
    PolkadotSurface(
        modifier = Modifier.fillMaxSize(),
        color = UpgradeUsernameScreenColors.screenBg,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .systemBarsPadding()
                .imePadding(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            PolkadotTopBar(
                navigationAction = rememberTopBarAction(
                    action = onBackClick,
                    icon = NovaIcons.Close
                ),
                titleAlignment = TopBarTitleAlignment.Center,
            )

            VerticalSpacer { mediumIncreased }

            NovaText(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = PolkadotTheme.spacings.large),
                text = stringResource(RCommon.string.upgrade_username_title),
                style = TitleStyle,
                color = UpgradeUsernameScreenColors.primaryText,
                textAlign = TextAlign.Center
            )

            VerticalSpacer { extraMedium }

            NovaText(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = PolkadotTheme.spacings.large),
                text = stringResource(RCommon.string.upgrade_username_description),
                style = DescriptionStyle,
                color = UpgradeUsernameScreenColors.description,
                textAlign = TextAlign.Center
            )

            VerticalSpacer { extraLarge }

            PickUsernameField(
                username = state.username,
                fieldState = state.fieldState,
                isEnabled = !state.isClaimingInProgress,
                onUsernameChanged = onUsernameChanged,
            )

            FillerSpacer()

            PolkadotTextButton(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = PolkadotTheme.spacings.large)
                    .padding(bottom = PolkadotTheme.spacings.mediumIncreased),
                text = stringResource(RCommon.string.upgrade_username_action_confirm),
                style = whiteCtaStyle(),
                shape = RoundedCornerShape(FieldRadius),
                enabled = state.fieldState == UpgradeUsernameFieldState.Available,
                loading = state.isClaimingInProgress,
                onClick = onClaimAction,
            )
        }
    }
}

@Composable
private fun PickUsernameField(
    modifier: Modifier = Modifier,
    username: String,
    fieldState: UpgradeUsernameFieldState,
    isEnabled: Boolean,
    onUsernameChanged: (String) -> Unit,
) {
    val borderColor = when (fieldState) {
        UpgradeUsernameFieldState.Available -> UpgradeUsernameScreenColors.available
        UpgradeUsernameFieldState.Taken,
        UpgradeUsernameFieldState.Invalid -> UpgradeUsernameScreenColors.error
        UpgradeUsernameFieldState.Neutral -> UpgradeUsernameScreenColors.fieldNeutralBorder
    }
    val backgroundColor = when (fieldState) {
        UpgradeUsernameFieldState.Available -> UpgradeUsernameScreenColors.availableBg
        UpgradeUsernameFieldState.Taken,
        UpgradeUsernameFieldState.Invalid -> UpgradeUsernameScreenColors.errorBg
        UpgradeUsernameFieldState.Neutral -> UpgradeUsernameScreenColors.fieldNeutralBg
    }
    val showErrorPill = fieldState == UpgradeUsernameFieldState.Taken

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = PolkadotTheme.spacings.large),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        PolkadotSurface(
            modifier = Modifier
                .fillMaxWidth()
                .height(FieldHeight),
            shape = RoundedCornerShape(FieldRadius),
            color = backgroundColor,
            border = BorderStroke(FieldBorder, borderColor),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(
                        horizontal = PolkadotTheme.spacings.mediumIncreased,
                        vertical = PolkadotTheme.spacings.extraMedium,
                    ),
                contentAlignment = Alignment.CenterStart,
            ) {
                if (username.isEmpty()) {
                    NovaText(
                        text = stringResource(RCommon.string.upgrade_username_field_placeholder),
                        style = FieldTextStyle,
                        color = UpgradeUsernameScreenColors.placeholder,
                    )
                }
                BasicTextField(
                    modifier = Modifier.fillMaxWidth(),
                    value = username,
                    onValueChange = onUsernameChanged,
                    enabled = isEnabled,
                    singleLine = true,
                    textStyle = FieldTextStyle.copy(color = UpgradeUsernameScreenColors.primaryText),
                    cursorBrush = SolidColor(UpgradeUsernameScreenColors.primaryText),
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.None,
                        autoCorrectEnabled = false,
                        imeAction = ImeAction.Done,
                    ),
                )
            }
        }

        AnimatedVisibility(visible = showErrorPill) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                VerticalSpacer { small }
                ErrorPill(text = stringResource(RCommon.string.upgrade_username_state_taken))
            }
        }
    }
}

@Composable
private fun ErrorPill(modifier: Modifier = Modifier, text: String) {
    PolkadotSurface(
        modifier = modifier,
        shape = RoundedCornerShape(ErrorPillRadius),
        color = UpgradeUsernameScreenColors.errorPillBg,
    ) {
        NovaText(
            modifier = Modifier.padding(
                horizontal = PolkadotTheme.spacings.small,
                vertical = PolkadotTheme.spacings.tiny,
            ),
            text = text,
            style = ErrorPillTextStyle,
            color = UpgradeUsernameScreenColors.error,
        )
    }
}

@Composable
private fun whiteCtaStyle(): PolkadotButtonStyle {
    val colors = PolkadotButtonColors(
        containerBrush = SolidColor(UpgradeUsernameScreenColors.ctaBackground),
        contentColor = UpgradeUsernameScreenColors.ctaContent,
        disabledContainerBrush = SolidColor(UpgradeUsernameScreenColors.ctaDisabledBackground),
        disabledContentColor = UpgradeUsernameScreenColors.ctaDisabledContent,
    )
    return remember(colors) {
        object : PolkadotButtonStyle {
            override val colors = colors
            override val rippleColor = UpgradeUsernameScreenColors.ctaContent
        }
    }
}

@Preview
@Composable
private fun UpgradeUsernameScreenPreview() {
    PolkadotTheme {
        UpgradeUsernameScreenInternal(
            state = UpgradeUsernameUiState(),
            onUsernameChanged = {},
            onClaimAction = {},
            onBackClick = {}
        )
    }
}
