@file:OptIn(ExperimentalMaterial3Api::class)

package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.instructions.compose

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.design.components.bottomsheet.NovaModalBottomSheet
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.VideocamOutlined
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.compose.EvidenceInstructionScreen
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.models.EvidenceInstructionItem
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.instructions.EvidenceVideoInstructionsContract
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.instructions.compose.components.PreconditionsBottomSheetContent
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun EvidenceVideoInstructionScreen(contract: EvidenceVideoInstructionsContract) {
    EvidenceInstructionScreen(
        onClose = contract::back,
        icon = NovaIcons.VideocamOutlined,
        title = stringResource(RCommon.string.evidence_video_instructions_title),
        items = rememberEvidenceVideoInstructionItems(),
        actionText = stringResource(RCommon.string.evidence_video_instructions_action_start_filming),
        onActionClick = contract::openVideoRecorderIfPossible
    )

    val preconditionUiState by contract.preconditionUiState.collectAsStateWithLifecycle()
    NovaModalBottomSheet(
        isVisible = preconditionUiState.isVisible,
        onDismissRequest = contract::dismissPrecondition
    ) {
        preconditionUiState.precondition?.let { precondition ->
            PreconditionsBottomSheetContent(
                precondition = precondition,
                onAccept = contract::dismissPrecondition,
                onIgnore = contract::ignorePrecondition
            )
        }
    }
}

@Composable
private fun rememberEvidenceVideoInstructionItems(): ImmutableList<EvidenceInstructionItem> = remember {
    persistentListOf(
        EvidenceInstructionItem(
            titleRes = RCommon.string.evidence_video_instructions_film_during_session_title,
            descriptionRes = RCommon.string.evidence_video_instructions_film_during_session_description
        ),
        EvidenceInstructionItem(
            titleRes = RCommon.string.evidence_video_instructions_partially_completed_title,
            descriptionRes = RCommon.string.evidence_video_instructions_partially_completed_description
        ),
        EvidenceInstructionItem(
            titleRes = RCommon.string.evidence_video_instructions_in_app_camera_title,
            descriptionRes = RCommon.string.evidence_video_instructions_in_app_camera_description
        ),
        EvidenceInstructionItem(
            titleRes = RCommon.string.evidence_video_instructions_continuous_take_title,
            descriptionRes = RCommon.string.evidence_video_instructions_continuous_take_description
        ),
        EvidenceInstructionItem(
            titleRes = RCommon.string.evidence_video_instructions_filming_style_title,
            descriptionRes = RCommon.string.evidence_video_instructions_filming_style_description
        ),
        EvidenceInstructionItem(
            titleRes = RCommon.string.evidence_video_instructions_assistance_title,
            descriptionRes = RCommon.string.evidence_video_instructions_assistance_description
        )
    )
}
