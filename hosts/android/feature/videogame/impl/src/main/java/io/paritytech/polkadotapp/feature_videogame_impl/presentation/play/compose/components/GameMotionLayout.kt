@file:OptIn(ExperimentalMotionApi::class)

package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.components

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationSpec
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.constraintlayout.compose.ConstraintSet
import androidx.constraintlayout.compose.ExperimentalMotionApi
import androidx.constraintlayout.compose.MotionLayout
import androidx.constraintlayout.compose.Transition
import kotlinx.coroutines.channels.Channel

@Composable
inline fun GameMotionLayout(
    modifier: Modifier = Modifier,
    transition: Transition? = null,
    config: ConstraintConfig,
    noinline finishedAnimationListener: (() -> Unit)? = null,
    noinline onProgressChanged: ((Float) -> Unit)? = null,
    crossinline content: @Composable () -> Unit
) {
    var startConstraint by remember { mutableStateOf(config.constraintSet) }
    var endConstraint by remember { mutableStateOf(config.constraintSet) }
    val progress = remember { Animatable(0.0f) }
    val channel = remember { Channel<ConstraintConfig>(Channel.CONFLATED) }
    val direction = remember { mutableIntStateOf(1) }

    if (config.snap) {
        startConstraint = config.constraintSet
        endConstraint = config.constraintSet
    }

    SideEffect { channel.trySend(config) }

    LaunchedEffect(channel) {
        for (config in channel) {
            val newConfig = channel.tryReceive().getOrNull() ?: config

            val currentConstraints = if (direction.intValue == 1) startConstraint else endConstraint

            if (newConfig.constraintSet != currentConstraints) {
                if (direction.intValue == 1) {
                    endConstraint = newConfig.constraintSet
                } else {
                    startConstraint = newConfig.constraintSet
                }
                progress.animateTo(direction.intValue.toFloat(), newConfig.animateChangesSpec)
                direction.intValue = if (direction.intValue == 1) 0 else 1
                finishedAnimationListener?.invoke()
            }
        }
    }

    if (onProgressChanged != null) {
        LaunchedEffect(progress.value) {
            onProgressChanged(progress.value)
        }
    }

    MotionLayout(
        start = startConstraint,
        end = endConstraint,
        progress = progress.value,
        modifier = modifier,
        content = { content() },
        transition = transition
    )
}

@Immutable
data class ConstraintConfig(
    val constraintSet: ConstraintSet,
    val animateChangesSpec: AnimationSpec<Float>,
    val transition: Transition? = null,
    val snap: Boolean = false
)
