package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.compose.components

import android.os.Build
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.draw.blur
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.theme.NovaPrizesColors

private val FRAME_OUTER_RADIUS = 16.dp
private val FRAME_INNER_RADIUS = 8.dp
private val FRAME_BORDER_THICKNESS = 8.dp

private val MEMBER_BANNER_VERTICAL_PADDING = 11.dp

private val BLUE_HALO_BLUR = 16.dp
private val GREEN_HALO_BLUR = 4.dp
private val YELLOW_HALO_BLUR = 4.dp

private val MemberBannerTextStyle = TextStyle(
    fontSize = 14.sp,
    lineHeight = 18.sp,
    fontWeight = FontWeight.SemiBold,
)

@Immutable
internal enum class UpcomingGameStickerPalette {
    BLUE, GREEN, YELLOW
}

@Composable
internal fun UpcomingGameStickerFrame(
    modifier: Modifier = Modifier,
    palette: UpcomingGameStickerPalette,
    membershipBanner: String? = null,
    content: @Composable () -> Unit,
) {
    val frameShape = RoundedCornerShape(FRAME_OUTER_RADIUS)
    val innerShape = RoundedCornerShape(FRAME_INNER_RADIUS)
    val supportsBlur = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
    // Reserve room for the blurred halo so it fades out within bounds instead of being clipped flat.
    val glowPadding = if (supportsBlur) palette.haloBlur() else 0.dp

    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = glowPadding),
    ) {
        if (supportsBlur) {
            PolkadotSurface(
                modifier = Modifier
                    .matchParentSize()
                    .blur(palette.haloBlur(), edgeTreatment = BlurredEdgeTreatment.Unbounded),
                shape = frameShape,
                color = palette.haloColor(),
            ) {}
        }

        PolkadotSurface(
            modifier = Modifier.fillMaxWidth(),
            shape = frameShape,
            brush = palette.strokeBrush(),
        ) {
            if (membershipBanner == null) {
                PolkadotSurface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(FRAME_BORDER_THICKNESS),
                    shape = innerShape,
                    color = NovaPrizesColors.cardInnerBg,
                ) {
                    content()
                }
            } else {
                PolkadotSurface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(FRAME_BORDER_THICKNESS),
                    shape = innerShape,
                    brush = palette.bannerBrush(),
                ) {
                    Column(modifier = Modifier.fillMaxWidth()) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = MEMBER_BANNER_VERTICAL_PADDING),
                            contentAlignment = Alignment.Center,
                        ) {
                            NovaText(
                                text = membershipBanner,
                                style = MemberBannerTextStyle,
                                color = palette.bannerTextColor(),
                                textAlign = TextAlign.Center,
                            )
                        }
                        PolkadotSurface(
                            modifier = Modifier.fillMaxWidth(),
                            shape = innerShape,
                            color = NovaPrizesColors.cardInnerBg,
                        ) {
                            content()
                        }
                    }
                }
            }
        }
    }
}

private fun UpcomingGameStickerPalette.bannerBrush(): Brush = when (this) {
    UpcomingGameStickerPalette.BLUE -> Brush.verticalGradient(
        colors = listOf(
            NovaPrizesColors.memberBannerBlueGradientTop,
            NovaPrizesColors.memberBannerBlueGradientBottom,
        )
    )
    UpcomingGameStickerPalette.GREEN -> Brush.verticalGradient(
        colors = listOf(
            NovaPrizesColors.memberBannerGreenGradientTop,
            NovaPrizesColors.memberBannerGreenGradientBottom,
        )
    )
    UpcomingGameStickerPalette.YELLOW -> Brush.verticalGradient(
        colors = listOf(
            NovaPrizesColors.memberBannerYellowGradientTop,
            NovaPrizesColors.memberBannerYellowGradientBottom,
        )
    )
}

private fun UpcomingGameStickerPalette.bannerTextColor(): Color = when (this) {
    UpcomingGameStickerPalette.BLUE -> NovaPrizesColors.memberBannerLightText
    UpcomingGameStickerPalette.GREEN -> NovaPrizesColors.memberBannerDarkText
    UpcomingGameStickerPalette.YELLOW -> NovaPrizesColors.memberBannerDarkText
}

private fun UpcomingGameStickerPalette.strokeBrush(): Brush = when (this) {
    UpcomingGameStickerPalette.BLUE -> Brush.verticalGradient(
        colors = listOf(
            NovaPrizesColors.stickerBlueStrokeTop,
            NovaPrizesColors.stickerBlueStrokeMid,
            NovaPrizesColors.stickerBlueStrokeBottom,
        )
    )
    UpcomingGameStickerPalette.GREEN -> Brush.verticalGradient(
        colors = listOf(
            NovaPrizesColors.stickerGreenStrokeTop,
            NovaPrizesColors.stickerGreenStrokeBottom,
        )
    )
    UpcomingGameStickerPalette.YELLOW -> Brush.verticalGradient(
        colors = listOf(
            NovaPrizesColors.stickerYellowStrokeTop,
            NovaPrizesColors.stickerYellowStrokeBottom,
        )
    )
}

private fun UpcomingGameStickerPalette.haloColor(): Color = when (this) {
    UpcomingGameStickerPalette.BLUE -> NovaPrizesColors.stickerBlueHalo
    UpcomingGameStickerPalette.GREEN -> NovaPrizesColors.stickerGreenHalo
    UpcomingGameStickerPalette.YELLOW -> NovaPrizesColors.stickerYellowHalo
}

private fun UpcomingGameStickerPalette.haloBlur(): Dp = when (this) {
    UpcomingGameStickerPalette.BLUE -> BLUE_HALO_BLUR
    UpcomingGameStickerPalette.GREEN -> GREEN_HALO_BLUR
    UpcomingGameStickerPalette.YELLOW -> YELLOW_HALO_BLUR
}
