package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.background

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.theme.ForceDarkBackgroundSystemBarsEffect
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatBackgroundRenderer
import io.paritytech.polkadotapp.feature_videogame_impl.R
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.theme.NovaPrizesColors

private const val PATTERN_ALPHA = 0.10f

internal class WeeklyGameBackgroundRenderer : CustomChatBackgroundRenderer {
    @Composable
    override fun DrawBackground() {
        ForceDarkBackgroundSystemBarsEffect()

        PolkadotSurface(
            modifier = Modifier.fillMaxSize(),
            brush = BASE_GRADIENT,
        ) {
            Image(
                modifier = Modifier.fillMaxSize(),
                painter = painterResource(R.drawable.chat_bot_prizes_pattern),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                alpha = PATTERN_ALPHA,
            )
        }
    }
}

private val BASE_GRADIENT = Brush.verticalGradient(
    colors = listOf(
        NovaPrizesColors.backgroundGradientTop,
        NovaPrizesColors.backgroundGradientBottom,
    ),
)
