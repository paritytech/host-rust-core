package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.constraints

import androidx.compose.ui.unit.dp
import androidx.constraintlayout.compose.ConstrainScope
import androidx.constraintlayout.compose.ConstrainedLayoutReference
import androidx.constraintlayout.compose.ConstraintSetScope
import androidx.constraintlayout.compose.Dimension
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.referenceId
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.sortResult
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.PlayerUiModel
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.VideoGameUiState
import kotlinx.collections.immutable.ImmutableList
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

const val LeftAnchorLayoutId = "anchor_left"
const val RightAnchorLayoutId = "anchor_right"

const val HostingIntroductionHeaderLayoutId = "hosting_introduction_header"
const val HostingIntroductionFooterLayoutId = "hosting_introduction_footer"
const val HostingProgressBarLayoutId = "hosting_progress_bar"
const val HowToPlayButtonLayoutId = "how_to_play_button"
const val ConnectingCountdownLayoutId = "connecting_countdown"

val VideoGameUiState.transitionDuration: Duration
    get() = when (this) {
        is VideoGameUiState.Initial -> Duration.ZERO
        is VideoGameUiState.WaitingRoom -> Duration.ZERO
        is VideoGameUiState.Connecting -> Duration.ZERO
        is VideoGameUiState.HostIntroduction -> 1.seconds
        is VideoGameUiState.Hosting -> 1.seconds
        is VideoGameUiState.HostReset -> 500.milliseconds
        is VideoGameUiState.Finished -> 1.seconds
        is VideoGameUiState.Error -> Duration.ZERO
    }

fun ConstrainScope.linkOutOfScreenByIndex(index: Int) {
    when (index) {
        0 -> {
            bottom.linkTo(parent.top)
            end.linkTo(parent.start)
        }

        1 -> {
            bottom.linkTo(parent.top)
            start.linkTo(parent.end)
        }

        2 -> {
            end.linkTo(parent.start)
            centerVerticallyTo(parent)
        }

        3 -> {
            start.linkTo(parent.end)
            centerVerticallyTo(parent)
        }

        4 -> {
            top.linkTo(parent.bottom)
            end.linkTo(parent.start)
        }

        5 -> {
            top.linkTo(parent.bottom)
            start.linkTo(parent.end)
        }
    }
}

fun ConstraintSetScope.setupGridAnchors(): Pair<ConstrainedLayoutReference, ConstrainedLayoutReference> {
    val anchorLeft = createRefFor(LeftAnchorLayoutId)
    val anchorRight = createRefFor(RightAnchorLayoutId)

    constrain(anchorLeft) {
        width = Dimension.fillToConstraints
        height = Dimension.ratio("1:1")

        start.linkTo(parent.start, margin = 8.dp)
        top.linkTo(parent.top)
        bottom.linkTo(parent.bottom)
        end.linkTo(anchorRight.start, margin = 4.dp)
    }

    constrain(anchorRight) {
        width = Dimension.fillToConstraints
        height = Dimension.ratio("1:1")

        start.linkTo(anchorLeft.end, margin = 4.dp)
        end.linkTo(parent.end, margin = 8.dp)
        top.linkTo(parent.top)
        bottom.linkTo(parent.bottom)
    }

    return anchorLeft to anchorRight
}

fun ConstraintSetScope.hideHostingIntroductionInfo() {
    val hostingIntroductionHeaderRef = createRefFor(HostingIntroductionHeaderLayoutId)
    val hostingIntroductionFooterRef = createRefFor(HostingIntroductionFooterLayoutId)

    constrain(hostingIntroductionHeaderRef) {
        width = Dimension.fillToConstraints

        start.linkTo(parent.start)
        end.linkTo(parent.end)

        bottom.linkTo(parent.top)
    }

    constrain(hostingIntroductionFooterRef) {
        width = Dimension.fillToConstraints

        start.linkTo(parent.start)
        end.linkTo(parent.end)

        top.linkTo(parent.bottom)
    }
}

fun ConstraintSetScope.showHostingIntroductionInfo(hostRef: ConstrainedLayoutReference) {
    val hostingIntroductionHeaderRef = createRefFor(HostingIntroductionHeaderLayoutId)
    val hostingIntroductionFooterRef = createRefFor(HostingIntroductionFooterLayoutId)

    constrain(hostingIntroductionHeaderRef) {
        width = Dimension.fillToConstraints

        start.linkTo(parent.start)
        end.linkTo(parent.end)

        bottom.linkTo(hostRef.top, margin = 32.dp)
    }
    constrain(hostingIntroductionFooterRef) {
        width = Dimension.fillToConstraints

        start.linkTo(parent.start)
        end.linkTo(parent.end)

        top.linkTo(hostRef.bottom, margin = 32.dp)
    }
}

fun ConstraintSetScope.hideHostingProgressBar() {
    val hostingProgressBarRef = createRefFor(HostingProgressBarLayoutId)

    constrain(hostingProgressBarRef) {
        start.linkTo(parent.start)
        end.linkTo(parent.end)

        top.linkTo(parent.bottom)
    }
}

fun ConstraintSetScope.showHostingProgressBar() {
    val hostingProgressBarRef = createRefFor(HostingProgressBarLayoutId)

    constrain(hostingProgressBarRef) {
        width = Dimension.fillToConstraints

        start.linkTo(parent.start)
        end.linkTo(parent.end)
        bottom.linkTo(parent.bottom)
    }
}

fun ConstraintSetScope.createPlayersGridConstraints(
    players: ImmutableList<PlayerUiModel>,
    anchorLeft: ConstrainedLayoutReference,
    anchorRight: ConstrainedLayoutReference,
) {
    val guideline = createGuidelineFromStart(0.5f)

    players
        .sortedBy { it.sortResult }
        .forEachIndexed { index, player ->
            val ref = createRefFor(player.referenceId)

            constrain(ref) {
                width = Dimension.fillToConstraints
                height = Dimension.ratio("1:1")

                if (index % 2 == 0) {
                    start.linkTo(parent.start, margin = 8.dp)
                    end.linkTo(guideline, margin = 4.dp)
                } else {
                    start.linkTo(guideline, margin = 4.dp)
                    end.linkTo(parent.end, margin = 8.dp)
                }

                val anchor = if (index % 2 == 0) anchorLeft else anchorRight
                val rowIndex = index / 2

                when (rowIndex) {
                    0 -> {
                        bottom.linkTo(anchor.top, margin = 8.dp)
                    }

                    1 -> {
                        top.linkTo(anchor.top)
                        bottom.linkTo(anchor.bottom)
                    }

                    else -> {
                        top.linkTo(anchor.bottom, margin = 8.dp)
                    }
                }
            }
        }
}

fun ConstraintSetScope.showConnectingCountdown() {
    val ref = createRefFor(ConnectingCountdownLayoutId)

    constrain(ref) {
        start.linkTo(parent.start)
        end.linkTo(parent.end)

        bottom.linkTo(parent.bottom)
    }
}

fun ConstraintSetScope.hideConnectingCountdown() {
    val ref = createRefFor(ConnectingCountdownLayoutId)

    constrain(ref) {
        start.linkTo(parent.start)
        end.linkTo(parent.end)

        top.linkTo(parent.bottom)
    }
}

fun ConstraintSetScope.hideHowToPlayButton() {
    val ref = createRefFor(HowToPlayButtonLayoutId)

    constrain(ref) {
        start.linkTo(parent.start)
        end.linkTo(parent.end)

        bottom.linkTo(parent.top)
    }
}

fun ConstraintSetScope.showHowToPlayButton() {
    val ref = createRefFor(HowToPlayButtonLayoutId)

    constrain(ref) {
        start.linkTo(parent.start)
        end.linkTo(parent.end)

        top.linkTo(parent.top, margin = 8.dp)
    }
}
