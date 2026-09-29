package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose

import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameTimings

fun <S> tooltipTransition(): AnimatedContentTransitionScope<S>.() -> ContentTransform {
    return {
        val animationSpec = tween<Float>(
            durationMillis = 200,
            easing = LinearEasing
        )

        val inAnimation = fadeIn(animationSpec = animationSpec) + scaleIn(initialScale = 0.9f, animationSpec = animationSpec)
        val outAnimation = fadeOut(animationSpec = animationSpec) + scaleOut(targetScale = 0.9f, animationSpec = animationSpec)

        inAnimation.togetherWith(outAnimation)
            .using(
                SizeTransform(clip = false)
            )
    }
}

fun tooltipDelay() = VideoGameTimings.HOST_ACTIVE_MINIMUM / 4
