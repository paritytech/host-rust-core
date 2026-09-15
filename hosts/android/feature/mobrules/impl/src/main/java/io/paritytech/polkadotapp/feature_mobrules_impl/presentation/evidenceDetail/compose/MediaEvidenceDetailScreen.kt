package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.compose

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.ui.compose.ContentFrame
import io.novasama.substrate_sdk_android.extensions.fromHex
import io.paritytech.polkadotapp.common.presentation.compose.video.VideoPlayerControlsContainer
import io.paritytech.polkadotapp.common.presentation.compose.video.rememberExoPlayer
import io.paritytech.polkadotapp.common.presentation.compose.video.toProgressiveMediaSource
import io.paritytech.polkadotapp.design.components.image.NovaAsyncImage
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImage
import io.paritytech.polkadotapp.feature_mobrules_impl.data.evidence.hashAsUri
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.compose.VotingButtons
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.CaseType
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.MediaEvidenceDetailContract
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.compose.components.MediaEvidenceThumbnailSwitcher
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.compose.components.MediaEvidenceTopBar
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.compose.components.VideoWatchCountdown
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.model.MediaEvidenceDetailUiState
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.model.MediaEvidenceThumbnail
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.model.VideoWatchingStatus
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.model.VotingOption
import io.paritytech.polkadotapp.tools_ipfs_api.IpfsImageRequest
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun MediaEvidenceDetailScreen(contract: MediaEvidenceDetailContract) {
    val state by contract.state.collectAsStateWithLifecycle()

    MediaEvidenceDetailScreenInternal(
        state = state,
        onVoteClick = contract::onVoteClick,
        onSelectThumbnail = contract::onSelectThumbnail,
        onVideoPlayingChanged = contract::onVideoPlayingChanged,
        onCloseClick = contract::onCloseClick,
        dataSourceFactory = contract.chunkedDataSourceFactory
    )
}

@Composable
private fun MediaEvidenceDetailScreenInternal(
    state: MediaEvidenceDetailUiState,
    onVoteClick: (VotingOption) -> Unit,
    onSelectThumbnail: (MediaEvidenceThumbnail) -> Unit,
    onVideoPlayingChanged: (Boolean) -> Unit,
    onCloseClick: () -> Unit,
    dataSourceFactory: DataSource.Factory
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .navigationBarsPadding()
    ) {
        val title = when (state.caseType) {
            CaseType.PHOTO -> stringResource(RCommon.string.mob_rule_bot_photo_title)
            CaseType.VIDEO -> stringResource(RCommon.string.mob_rule_bot_video_title)
        }

        MediaEvidenceTopBar(
            title = title,
            subtitle = stringResource(RCommon.string.mob_rule_case_subtitle, state.caseId),
            onClose = onCloseClick
        )

        val pagerState = rememberPagerState(
            initialPage = state.selectedThumbnail.ordinal,
            pageCount = { MediaEvidenceThumbnail.entries.size }
        )

        LaunchedEffect(state.selectedThumbnail) {
            if (pagerState.currentPage != state.selectedThumbnail.ordinal) {
                pagerState.animateScrollToPage(state.selectedThumbnail.ordinal)
            }
        }

        LaunchedEffect(pagerState.settledPage) {
            val thumbnail = MediaEvidenceThumbnail.entries[pagerState.settledPage]
            onSelectThumbnail(thumbnail)
        }

        Spacer(modifier = Modifier.weight(1f))

        HorizontalPager(
            state = pagerState,
            modifier = Modifier.fillMaxWidth()
        ) { page ->
            when (MediaEvidenceThumbnail.entries[page]) {
                MediaEvidenceThumbnail.EVIDENCE -> when (state.caseType) {
                    CaseType.PHOTO -> PhotoEvidenceContent(
                        evidenceHashHex = state.evidenceHashHex
                    )

                    CaseType.VIDEO -> VideoEvidenceContent(
                        evidenceHashHex = state.evidenceHashHex,
                        dataSourceFactory = dataSourceFactory,
                        onVideoPlayingChanged = onVideoPlayingChanged
                    )
                }

                MediaEvidenceThumbnail.TATTOO -> TattooImageContent(
                    tattooImage = state.tattooImage
                )
            }
        }

        Spacer(modifier = Modifier.weight(1f))

        MediaEvidenceThumbnailSwitcher(
            modifier = Modifier.padding(bottom = PolkadotTheme.spacings.large),
            evidenceHashHex = state.evidenceHashHex,
            tattooImage = state.tattooImage,
            selectedThumbnail = state.selectedThumbnail,
            onSelectThumbnail = onSelectThumbnail,
        )

        if (!state.viewOnly) {
            when (state.videoWatchingStatus) {
                is VideoWatchingStatus.NotRequired,
                is VideoWatchingStatus.Watched -> {
                    PolkadotSurface(
                        shape = RoundedCornerShape(48.dp),
                        color = Color(0x14FFFFFF),
                        border = BorderStroke(PolkadotTheme.borders.default, PolkadotTheme.colors.stroke.primary),
                        modifier = Modifier.padding(horizontal = PolkadotTheme.spacings.small)
                    ) {
                        VotingButtons(
                            modifier = Modifier.padding(PolkadotTheme.spacings.small),
                            onVote = onVoteClick
                        )
                    }
                }
                is VideoWatchingStatus.Countdown -> VideoWatchCountdown(
                    modifier = Modifier.padding(horizontal = PolkadotTheme.spacings.mediumIncreased),
                    secondsRemaining = state.videoWatchingStatus.secondsRemaining
                )
            }
        }
    }
}

@Composable
private fun TattooImageContent(tattooImage: TattooImage) {
    NovaAsyncImage(
        model = tattooImage.loadable,
        contentScale = ContentScale.Fit,
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(1f)
            .background(PolkadotTheme.colors.fg.staticWhite)
    )
}

@Composable
private fun PhotoEvidenceContent(evidenceHashHex: String) {
    val evidenceImageModel = remember(evidenceHashHex) { IpfsImageRequest(evidenceHashHex.fromHex()) }

    NovaAsyncImage(
        model = evidenceImageModel,
        contentScale = ContentScale.Fit,
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(1f)
    )
}

@Composable
private fun VideoEvidenceContent(
    evidenceHashHex: String,
    dataSourceFactory: DataSource.Factory,
    onVideoPlayingChanged: (Boolean) -> Unit
) {
    val mediaSource = remember(evidenceHashHex) {
        evidenceHashHex.fromHex().hashAsUri().toProgressiveMediaSource(dataSourceFactory)
    }
    val player = rememberExoPlayer(mediaSource = mediaSource, playWhenReady = false)

    VideoPlayerControlsContainer(
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(1f),
        player = player,
        onPlayingChanged = onVideoPlayingChanged
    ) {
        ContentFrame(
            modifier = Modifier
                .fillMaxSize()
                .clipToBounds(),
            player = player,
            contentScale = ContentScale.Fit
        )
    }
}

@UnstableApi
@Preview
@Composable
private fun MediaEvidenceDetailScreenPreview() {
    PolkadotTheme {
        MediaEvidenceDetailScreenInternal(
            state = MediaEvidenceDetailUiState(
                caseType = CaseType.PHOTO,
                caseId = "42",
            ),
            onVoteClick = {},
            onSelectThumbnail = {},
            onVideoPlayingChanged = {},
            onCloseClick = {},
            dataSourceFactory = { error("preview") }
        )
    }
}
