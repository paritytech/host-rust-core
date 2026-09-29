package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonColors
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonStyle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_videogame_impl.R
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.GameColors
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.TutorialPage
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.VideoGameTutorialState
import kotlinx.coroutines.launch
import kotlin.math.abs
import io.paritytech.polkadotapp.common.R as RCommon

private val TutorialPages = listOf(
    TutorialPage(
        RCommon.string.video_game_tutorial_first_step,
        R.drawable.img_tutorial_gestures
    ),
    TutorialPage(
        RCommon.string.video_game_tutorial_second_step,
        R.drawable.img_tutorial_voting
    )
)

@Composable
fun VideoGameTutorialOverlay(
    tutorialState: VideoGameTutorialState,
    onDone: () -> Unit
) {
    if (tutorialState is VideoGameTutorialState.Shown) {
        val scope = rememberCoroutineScope()
        val pagerState = rememberPagerState(pageCount = { TutorialPages.size })

        val isLastPage = pagerState.currentPage == TutorialPages.lastIndex

        PolkadotSurface(
            modifier = Modifier
                .fillMaxSize(),
            color = GameColors.backgroundPrimary
        ) {
            Column(
                modifier = Modifier
                    .statusBarsPadding()
                    .navigationBarsPadding()
                    .padding(vertical = PolkadotTheme.spacings.mediumIncreased)
                    .clickable(onClick = {}), // Nothing is here. Just override click to prevent any click under overlay
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                PagerIndicator(pagerState = pagerState)

                VerticalSpacer { PolkadotTheme.spacings.extraLargeIncreased }

                HorizontalPager(
                    state = pagerState,
                    modifier = Modifier
                        .weight(1f),
                    overscrollEffect = null
                ) { page ->
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(horizontal = PolkadotTheme.spacings.mediumIncreased),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        NovaText(
                            text = stringResource(TutorialPages[page].titleRes),
                            style = PolkadotTheme.typography.headline.large.copy(
                                fontSize = 38.sp,
                                lineHeight = 38.sp,
                                fontWeight = FontWeight.ExtraBold,
                                letterSpacing = 0.sp,
                            ),
                            color = GameColors.textOnGameBackground,
                            textAlign = TextAlign.Center
                        )

                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .weight(1f),
                            contentAlignment = Alignment.Center
                        ) {
                            Image(
                                painter = painterResource(TutorialPages[page].imageRes),
                                contentDescription = null,
                                contentScale = ContentScale.Fit,
                            )
                        }
                    }
                }

                PolkadotTextButton(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = PolkadotTheme.spacings.mediumIncreased),
                    text = if (isLastPage) {
                        stringResource(RCommon.string.common_done)
                    } else {
                        stringResource(RCommon.string.common_next)
                    },
                    style = tutorialCtaStyle(),
                    onClick = {
                        if (isLastPage) {
                            onDone()
                        } else {
                            scope.launch {
                                pagerState.animateScrollToPage(pagerState.currentPage + 1)
                            }
                        }
                    }
                )
            }
        }
    }
}

@Composable
private fun tutorialCtaStyle(): PolkadotButtonStyle {
    val background = GameColors.tutorialButtonBackground
    val content = GameColors.tutorialButtonContent
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

@Composable
fun PagerIndicator(pagerState: PagerState) {
    val activeColor = GameColors.textOnGameBackground
    val inactiveColor = GameColors.tutorialPagerInactive

    Row(
        modifier = Modifier
            .fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        repeat(pagerState.pageCount) { iteration ->
            val pageOffset = (pagerState.currentPage - iteration) + pagerState.currentPageOffsetFraction

            val fraction = (1f - abs(pageOffset)).coerceIn(0f, 1f)

            val color = lerp(inactiveColor, activeColor, fraction)

            PolkadotSurface(
                modifier = Modifier
                    .padding(PolkadotTheme.spacings.tiny)
                    .size(12.dp),
                shape = PolkadotTheme.shapes.full,
                color = color
            ) { }
        }
    }
}

@Preview
@Composable
private fun TutorialPreview() {
    PolkadotTheme {
        VideoGameTutorialOverlay(
            tutorialState = VideoGameTutorialState.Shown,
            onDone = {}
        )
    }
}
