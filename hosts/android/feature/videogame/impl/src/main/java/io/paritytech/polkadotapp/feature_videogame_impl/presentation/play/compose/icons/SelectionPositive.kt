package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.icons

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

val SelectionPositive: ImageVector by lazy(LazyThreadSafetyMode.NONE) {
    ImageVector.Builder(
        name = "SelectionPositive",
        defaultWidth = 112.dp,
        defaultHeight = 112.dp,
        viewportWidth = 112f,
        viewportHeight = 112f
    ).apply {
        path(
            stroke = SolidColor(Color(0xFF34C759)),
            strokeLineWidth = 18f,
            strokeLineCap = StrokeCap.Round
        ) {
            moveTo(20f, 61.89f)
            lineTo(40.48f, 87.01f)
            curveTo(41.31f, 88.02f, 42.86f, 87.99f, 43.64f, 86.94f)
            lineTo(92f, 22f)
        }
    }.build()
}
