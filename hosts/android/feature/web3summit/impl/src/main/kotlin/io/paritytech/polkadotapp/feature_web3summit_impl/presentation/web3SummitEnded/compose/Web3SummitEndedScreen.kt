package io.paritytech.polkadotapp.feature_web3summit_impl.presentation.web3SummitEnded.compose

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_web3summit_impl.presentation.web3SummitEnded.Web3SummitEndedViewModel
import kotlinx.coroutines.delay
import io.paritytech.polkadotapp.common.R as RCommon

private const val PER_WORD_DELAY_MILLIS = 90L
private const val WORD_FADE_DURATION_MILLIS = 250
private val WORD_RISE_OFFSET: Dp = 28.dp

@Composable
@Suppress("UNUSED_PARAMETER")
fun Web3SummitEndedScreen(viewModel: Web3SummitEndedViewModel) {
    val message = stringResource(RCommon.string.w3s_ended)

    PolkadotSurface(modifier = Modifier.fillMaxSize()) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center,
        ) {
            AnimatedWordsMessage(
                modifier = Modifier.padding(PolkadotTheme.spacings.extraLarge),
                text = message,
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AnimatedWordsMessage(modifier: Modifier = Modifier, text: String) {
    val words = remember(text) { text.split(' ') }

    FlowRow(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.small, Alignment.CenterHorizontally),
        verticalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.small),
    ) {
        words.forEachIndexed { index, word ->
            AnimatedWord(word = word, delayMillis = index * PER_WORD_DELAY_MILLIS)
        }
    }
}

@Composable
private fun AnimatedWord(word: String, delayMillis: Long) {
    var visible by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        delay(delayMillis)
        visible = true
    }
    val alpha by animateFloatAsState(
        targetValue = if (visible) 1f else 0f,
        animationSpec = tween(WORD_FADE_DURATION_MILLIS),
        label = "w3s_ended_word_alpha"
    )
    val rise by animateFloatAsState(
        targetValue = if (visible) 0f else 1f,
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioMediumBouncy,
            stiffness = Spring.StiffnessMediumLow,
        ),
        label = "w3s_ended_word_rise"
    )

    NovaText(
        modifier = Modifier.graphicsLayer {
            this.alpha = alpha
            translationY = rise * WORD_RISE_OFFSET.toPx()
        },
        text = word,
        style = PolkadotTheme.typography.display.medium,
        color = PolkadotTheme.colors.fg.primary,
        textAlign = TextAlign.Center,
    )
}
