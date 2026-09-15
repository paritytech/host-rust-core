package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.compose.components

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import io.paritytech.polkadotapp.feature_people_api.presentation.compose.DimSwitchConfirmationContent
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun SwitchToDim2ConfirmationContent(
    onConfirm: () -> Unit,
    onCancel: () -> Unit,
    inProgress: Boolean
) {
    DimSwitchConfirmationContent(
        title = stringResource(RCommon.string.dim_switch_to_dim2_sheet_title),
        description = stringResource(RCommon.string.dim_switch_to_dim2_sheet_description),
        cancelText = stringResource(RCommon.string.common_cancel),
        confirmText = stringResource(RCommon.string.common_switch),
        onConfirm = onConfirm,
        onCancel = onCancel,
        inProgress = inProgress
    )
}
