package io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.components.icons

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.icon.NovaIcons

val NovaIcons.TouchGesture: ImageVector by lazy(LazyThreadSafetyMode.NONE) {
    ImageVector.Builder(
        name = "TouchGesture",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f
    ).apply {
        path(fill = SolidColor(Color.Black)) {
            moveTo(8.75f, 9.74f)
            verticalLineTo(6f)
            curveTo(8.75f, 4.62f, 9.87f, 3.5f, 11.25f, 3.5f)
            curveTo(12.63f, 3.5f, 13.75f, 4.62f, 13.75f, 6f)
            verticalLineTo(9.74f)
            curveTo(14.96f, 8.93f, 15.75f, 7.56f, 15.75f, 6f)
            curveTo(15.75f, 3.51f, 13.74f, 1.5f, 11.25f, 1.5f)
            curveTo(8.76f, 1.5f, 6.75f, 3.51f, 6.75f, 6f)
            curveTo(6.75f, 7.56f, 7.54f, 8.93f, 8.75f, 9.74f)
            close()
            moveTo(18.59f, 14.37f)
            lineTo(14.05f, 12.11f)
            curveTo(13.88f, 12.04f, 13.7f, 12f, 13.51f, 12f)
            horizontalLineTo(12.75f)
            verticalLineTo(6f)
            curveTo(12.75f, 5.17f, 12.08f, 4.5f, 11.25f, 4.5f)
            curveTo(10.42f, 4.5f, 9.75f, 5.17f, 9.75f, 6f)
            verticalLineTo(16.74f)
            curveTo(6.15f, 15.98f, 6.21f, 15.99f, 6.08f, 15.99f)
            curveTo(5.77f, 15.99f, 5.49f, 16.12f, 5.29f, 16.32f)
            lineTo(4.5f, 17.12f)
            lineTo(9.44f, 22.06f)
            curveTo(9.71f, 22.33f, 10.09f, 22.5f, 10.5f, 22.5f)
            horizontalLineTo(17.29f)
            curveTo(18.04f, 22.5f, 18.62f, 21.95f, 18.73f, 21.22f)
            lineTo(19.48f, 15.95f)
            curveTo(19.49f, 15.88f, 19.5f, 15.81f, 19.5f, 15.75f)
            curveTo(19.5f, 15.13f, 19.12f, 14.59f, 18.59f, 14.37f)
            close()
        }
    }.build()
}
