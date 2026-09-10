package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.compose

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.placeholder.DimSwitchPlaceholder
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.bot.TattooBotState
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.model.TattooBotUiState
import io.paritytech.polkadotapp.feature_chats_api.presentation.common.ChatFooterNavigationButton
import io.paritytech.polkadotapp.feature_upgrade_username_api.presentation.bot.UpgradeUsernameWidget
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun TattooBotFooter(
    state: TattooBotUiState,
    onSelectAndReserveTattooClick: () -> Unit,
    onFilmVideoClick: () -> Unit,
    onTakePhotoClick: () -> Unit,
    onUpgradeUsernameClick: () -> Unit,
    onNavigationToDim2Click: () -> Unit,
    onNavigationToMobRuleClick: () -> Unit,
    onEditClick: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = PolkadotTheme.spacings.mediumIncreased),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        when (state.botState) {
            TattooBotState.INITIALIZING -> Unit
            TattooBotState.TATTOO_SELECTION -> {
                PolkadotTextButton(
                    modifier = Modifier.fillMaxWidth(),
                    text = stringResource(RCommon.string.chat_bot_tattoo_select_and_reserve_tattoo_action),
                    onClick = onSelectAndReserveTattooClick
                )
            }

            TattooBotState.WAITING_FOR_VIDEO_EVIDENCE -> {
                NovaText(
                    text = stringResource(RCommon.string.chat_bot_tattoo_film_video_header),
                    style = PolkadotTheme.typography.body.medium,
                    color = PolkadotTheme.colors.fg.secondary
                )

                VerticalSpacer { mediumIncreased }

                PolkadotTextButton(
                    modifier = Modifier.fillMaxWidth(),
                    text = stringResource(RCommon.string.chat_bot_tattoo_film_video_action),
                    onClick = onFilmVideoClick
                )
            }

            TattooBotState.WAITING_FOR_PHOTO_EVIDENCE -> {
                NovaText(
                    text = stringResource(RCommon.string.chat_bot_tattoo_take_photo_header),
                    style = PolkadotTheme.typography.body.medium,
                    color = PolkadotTheme.colors.fg.secondary
                )

                VerticalSpacer { mediumIncreased }

                PolkadotTextButton(
                    modifier = Modifier.fillMaxWidth(),
                    text = stringResource(RCommon.string.chat_bot_tattoo_take_photo_action),
                    onClick = onTakePhotoClick
                )
            }

            TattooBotState.WAITING_FOR_CONFIRMATION -> {
                NovaText(
                    modifier = Modifier.padding(horizontal = PolkadotTheme.spacings.small),
                    text = stringResource(RCommon.string.chat_bot_tattoo_evidence_provided_description),
                    style = PolkadotTheme.typography.body.medium,
                    color = PolkadotTheme.colors.fg.secondary,
                    textAlign = TextAlign.Center
                )
            }

            TattooBotState.EVIDENCES_CONFIRMED -> {
                NovaText(
                    text = stringResource(RCommon.string.chat_bot_tattoo_evidence_approved_description_title),
                    style = PolkadotTheme.typography.body.mediumEmphasized,
                    color = PolkadotTheme.colors.fg.secondary,
                    textAlign = TextAlign.Center
                )
                NovaText(
                    text = stringResource(RCommon.string.chat_bot_tattoo_evidence_approved_description_subtitle),
                    style = PolkadotTheme.typography.body.medium,
                    color = PolkadotTheme.colors.fg.secondary,
                    textAlign = TextAlign.Center
                )
            }
            TattooBotState.OTHER_DIM_COMMITMENT,
            TattooBotState.OTHER_DIM_IN_PROGRESS -> {
                if (state.upgradeUsernameUiState == null) {
                    DimSwitchPlaceholder(
                        text = stringResource(RCommon.string.dim_switch_to_dim2_placeholder),
                        buttonText = stringResource(RCommon.string.common_edit),
                        onEditClick = onEditClick
                    )
                }
            }

            TattooBotState.REGISTERED_PERSON -> Unit
            TattooBotState.UNRECOVERABLE_ERROR -> {
                NovaText(
                    text = stringResource(RCommon.string.chat_bot_tattoo_unrecoverable_error),
                    style = PolkadotTheme.typography.body.medium,
                    color = PolkadotTheme.colors.fg.error,
                    textAlign = TextAlign.Center
                )
            }
        }

        state.upgradeUsernameUiState?.let {
            val maxWidthModifier = Modifier.fillMaxWidth()

            if (!it.isUpgraded) {
                UpgradeUsernameWidget(
                    modifier = maxWidthModifier,
                    usernameWithoutSuffix = it.fullName,
                    isUpgraded = false
                )

                VerticalSpacer { tiny }

                PolkadotTextButton(
                    modifier = Modifier.fillMaxWidth(),
                    text = stringResource(R.string.upgrade_username_CTA),
                    onClick = onUpgradeUsernameClick
                )

                VerticalSpacer { small }
            }

            VerticalSpacer { small }

            ChatFooterNavigationButton(
                modifier = maxWidthModifier,
                title = stringResource(R.string.chat_dim2_navigation_button_title),
                description = stringResource(R.string.chat_dim2_navigation_button_description),
                actionName = stringResource(R.string.common_open),
                onClick = onNavigationToDim2Click
            )

            VerticalSpacer { small }

            ChatFooterNavigationButton(
                modifier = maxWidthModifier,
                title = stringResource(R.string.chat_mob_rule_navigation_button_title),
                description = stringResource(R.string.chat_mob_rule_navigation_button_description),
                actionName = stringResource(R.string.common_open),
                onClick = onNavigationToMobRuleClick
            )
        }
    }
}
