package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.icons

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

val Music: ImageVector by lazy(LazyThreadSafetyMode.NONE) {
    ImageVector.Builder(
        name = "Music",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f
    ).apply {
        path(
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 2f,
            strokeLineCap = StrokeCap.Round,
            strokeLineJoin = StrokeJoin.Round
        ) {
            // circle cx=8, cy=18, r=4
            moveTo(12f, 18f)
            arcTo(4f, 4f, 0f, isMoreThanHalf = true, isPositiveArc = true, 4f, 18f)
            arcTo(4f, 4f, 0f, isMoreThanHalf = true, isPositiveArc = true, 12f, 18f)
        }
        path(
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 2f,
            strokeLineCap = StrokeCap.Round,
            strokeLineJoin = StrokeJoin.Round
        ) {
            // M12 18V2l7 4
            moveTo(12f, 18f)
            verticalLineTo(2f)
            lineTo(19f, 6f)
        }
    }.build()
}
