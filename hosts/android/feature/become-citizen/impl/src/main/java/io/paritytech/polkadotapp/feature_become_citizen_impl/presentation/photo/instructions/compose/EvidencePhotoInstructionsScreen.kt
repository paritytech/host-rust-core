@file:OptIn(ExperimentalMaterial3Api::class)

package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.instructions.compose

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.res.stringResource
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.Photocam
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.compose.EvidenceInstructionScreen
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.models.EvidenceInstructionItem
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.instructions.EvidencePhotoInstructionsContract
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun EvidencePhotoInstructionScreen(contract: EvidencePhotoInstructionsContract) {
    EvidenceInstructionScreen(
        onClose = contract::back,
        icon = NovaIcons.Photocam,
        title = stringResource(RCommon.string.evidence_photo_instructions_title),
        items = rememberEvidencePhotoInstructionItems(),
        actionText = stringResource(RCommon.string.evidence_photo_instructions_action_take_photo),
        onActionClick = contract::openTakePhoto
    )
}

@Composable
private fun rememberEvidencePhotoInstructionItems(): ImmutableList<EvidenceInstructionItem> = remember {
    persistentListOf(
        EvidenceInstructionItem(
            titleRes = RCommon.string.evidence_photo_instructions_in_app_camera_title,
            descriptionRes = RCommon.string.evidence_photo_instructions_in_app_camera_description
        ),
        EvidenceInstructionItem(
            titleRes = RCommon.string.evidence_photo_instructions_show_full_tattoo_title,
            descriptionRes = RCommon.string.evidence_photo_instructions_show_full_tattoo_description
        ),
        EvidenceInstructionItem(
            titleRes = RCommon.string.evidence_photo_instructions_assistance_title,
            descriptionRes = RCommon.string.evidence_photo_instructions_assistance_description
        )
    )
}
