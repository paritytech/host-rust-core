package io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.components.icons

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathData
import androidx.compose.ui.graphics.vector.group
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.icon.NovaIcons

val NovaIcons.FrontHand: ImageVector by lazy(LazyThreadSafetyMode.NONE) {
    ImageVector.Builder(
        name = "FrontHand",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f
    ).apply {
        group(
            clipPathData = PathData {
                moveTo(0f, 0f)
                horizontalLineToRelative(24f)
                verticalLineToRelative(24f)
                horizontalLineToRelative(-24f)
                close()
            }
        ) {
            path(fill = SolidColor(Color.Black)) {
                moveTo(19f, 8f)
                curveTo(18.31f, 8f, 17.75f, 8.56f, 17.75f, 9.25f)
                verticalLineTo(15f)
                horizontalLineTo(17.25f)
                curveTo(15.6f, 15f, 14.25f, 16.35f, 14.25f, 18f)
                horizontalLineTo(13.25f)
                curveTo(13.25f, 15.96f, 14.78f, 14.28f, 16.75f, 14.03f)
                verticalLineTo(3.25f)
                curveTo(16.75f, 2.56f, 16.19f, 2f, 15.5f, 2f)
                curveTo(14.81f, 2f, 14.25f, 2.56f, 14.25f, 3.25f)
                verticalLineTo(11f)
                horizontalLineTo(13.25f)
                verticalLineTo(1.25f)
                curveTo(13.25f, 0.56f, 12.69f, 0f, 12f, 0f)
                curveTo(11.31f, 0f, 10.75f, 0.56f, 10.75f, 1.25f)
                verticalLineTo(11f)
                horizontalLineTo(9.75f)
                verticalLineTo(2.75f)
                curveTo(9.75f, 2.06f, 9.19f, 1.5f, 8.5f, 1.5f)
                curveTo(7.81f, 1.5f, 7.25f, 2.06f, 7.25f, 2.75f)
                verticalLineTo(12f)
                horizontalLineTo(6.25f)
                verticalLineTo(5.75f)
                curveTo(6.25f, 5.06f, 5.69f, 4.5f, 5f, 4.5f)
                curveTo(4.31f, 4.5f, 3.75f, 5.06f, 3.75f, 5.75f)
                lineTo(3.75f, 15.75f)
                curveTo(3.75f, 20.31f, 7.44f, 24f, 12f, 24f)
                curveTo(16.56f, 24f, 20.25f, 20.31f, 20.25f, 15.75f)
                verticalLineTo(9.25f)
                curveTo(20.25f, 8.56f, 19.69f, 8f, 19f, 8f)
                close()
            }
        }
    }.build()
}
