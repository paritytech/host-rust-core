package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.model

import androidx.compose.runtime.Immutable
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImage
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.CaseType

enum class MediaEvidenceThumbnail {
    EVIDENCE, TATTOO
}

@Immutable
sealed interface VideoWatchingStatus {
    data object NotRequired : VideoWatchingStatus
    data class Countdown(val secondsRemaining: Int) : VideoWatchingStatus
    data object Watched : VideoWatchingStatus
}

@Immutable
data class MediaEvidenceDetailUiState(
    val caseType: CaseType = CaseType.PHOTO,
    val caseId: String = "",
    val tattooImage: TattooImage = TattooImage.Empty,
    val evidenceHashHex: String = "",
    val viewOnly: Boolean = false,
    val videoWatchingStatus: VideoWatchingStatus = VideoWatchingStatus.NotRequired,
    val selectedThumbnail: MediaEvidenceThumbnail = MediaEvidenceThumbnail.EVIDENCE
)
