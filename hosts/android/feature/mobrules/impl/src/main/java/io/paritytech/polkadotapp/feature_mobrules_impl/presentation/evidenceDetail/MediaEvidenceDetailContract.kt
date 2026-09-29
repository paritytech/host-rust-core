package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail

import androidx.media3.datasource.DataSource
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.model.MediaEvidenceDetailUiState
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.model.MediaEvidenceThumbnail
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.model.VotingOption
import kotlinx.coroutines.flow.StateFlow

interface MediaEvidenceDetailContract {
    val state: StateFlow<MediaEvidenceDetailUiState>

    val chunkedDataSourceFactory: DataSource.Factory

    fun onVoteClick(option: VotingOption)

    fun onSelectThumbnail(thumbnail: MediaEvidenceThumbnail)

    fun onVideoPlayingChanged(isPlaying: Boolean)

    fun onCloseClick()
}
