package io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.components.icons

import androidx.compose.foundation.shape.GenericShape
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Matrix
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.icon.NovaIcons

private const val SHAPE_REF_WIDTH = 240f
private const val SHAPE_REF_HEIGHT = 48f

val NovaIcons.CloudTooltip: ImageVector by lazy(LazyThreadSafetyMode.NONE) {
    ImageVector.Builder(
        name = "CloudTooltip",
        defaultWidth = 240.dp,
        defaultHeight = 52.dp,
        viewportWidth = 240f,
        viewportHeight = 52f
    ).apply {
        path(fill = SolidColor(Color.Black)) {
            moveTo(24f, 2f)
            curveTo(32f, 0f, 48f, 0f, 56f, 2f)
            curveTo(64f, 0f, 80f, 0f, 88f, 2f)
            curveTo(96f, 0f, 112f, 0f, 120f, 2f)
            curveTo(128f, 0f, 144f, 0f, 152f, 2f)
            curveTo(160f, 0f, 176f, 0f, 184f, 2f)
            curveTo(192f, 0f, 208f, 0f, 216f, 2f)
            curveTo(229.25f, 2f, 240f, 12.75f, 240f, 26f)
            curveTo(240f, 39.25f, 229.25f, 50f, 216f, 50f)
            curveTo(208f, 52f, 192f, 52f, 184f, 50f)
            curveTo(176f, 52f, 160f, 52f, 152f, 50f)
            curveTo(144f, 52f, 128f, 52f, 120f, 50f)
            curveTo(112f, 52f, 96f, 52f, 88f, 50f)
            curveTo(80f, 52f, 64f, 52f, 56f, 50f)
            curveTo(48f, 52f, 32f, 52f, 24f, 50f)
            curveTo(10.75f, 50f, 0f, 39.25f, 0f, 26f)
            curveTo(0f, 12.75f, 10.75f, 2f, 24f, 2f)
            close()
        }
    }.build()
}

internal val CloudTooltipShape: Shape = GenericShape { size, _ ->
    moveTo(24f, 0f)
    cubicTo(32f, -2f, 48f, -2f, 56f, 0f)
    cubicTo(64f, -2f, 80f, -2f, 88f, 0f)
    cubicTo(96f, -2f, 112f, -2f, 120f, 0f)
    cubicTo(128f, -2f, 144f, -2f, 152f, 0f)
    cubicTo(160f, -2f, 176f, -2f, 184f, 0f)
    cubicTo(192f, -2f, 208f, -2f, 216f, 0f)
    cubicTo(229.25f, 0f, 240f, 10.75f, 240f, 24f)
    cubicTo(240f, 37.25f, 229.25f, 48f, 216f, 48f)
    cubicTo(208f, 50f, 192f, 50f, 184f, 48f)
    cubicTo(176f, 50f, 160f, 50f, 152f, 48f)
    cubicTo(144f, 50f, 128f, 50f, 120f, 48f)
    cubicTo(112f, 50f, 96f, 50f, 88f, 48f)
    cubicTo(80f, 50f, 64f, 50f, 56f, 48f)
    cubicTo(48f, 50f, 32f, 50f, 24f, 48f)
    cubicTo(10.75f, 48f, 0f, 37.25f, 0f, 24f)
    cubicTo(0f, 10.75f, 10.75f, 0f, 24f, 0f)
    close()

    transform(Matrix().apply {
        scale(size.width / SHAPE_REF_WIDTH, size.height / SHAPE_REF_HEIGHT)
    })
}
