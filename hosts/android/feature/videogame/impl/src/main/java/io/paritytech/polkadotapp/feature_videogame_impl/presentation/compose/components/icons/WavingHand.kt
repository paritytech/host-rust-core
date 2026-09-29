package io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.components.icons

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.icon.NovaIcons

val NovaIcons.WavingHand: ImageVector by lazy(LazyThreadSafetyMode.NONE) {
    ImageVector.Builder(
        name = "WavingHand",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f
    ).apply {
        path(fill = SolidColor(Color.Black)) {
            moveTo(23.003f, 16.997f)
            curveTo(23.003f, 20.308f, 20.313f, 22.997f, 17.003f, 22.997f)
            verticalLineTo(21.497f)
            curveTo(19.483f, 21.497f, 21.503f, 19.478f, 21.503f, 16.997f)
            horizontalLineTo(23.003f)
            close()
            moveTo(1.003f, 6.997f)
            curveTo(1.003f, 3.688f, 3.693f, 0.997f, 7.003f, 0.997f)
            verticalLineTo(2.497f)
            curveTo(4.523f, 2.497f, 2.503f, 4.517f, 2.503f, 6.997f)
            horizontalLineTo(1.003f)
            close()
            moveTo(8.012f, 4.318f)
            lineTo(3.412f, 8.917f)
            curveTo(0.192f, 12.137f, 0.192f, 17.368f, 3.412f, 20.587f)
            curveTo(6.633f, 23.808f, 11.863f, 23.808f, 15.083f, 20.587f)
            lineTo(22.153f, 13.517f)
            curveTo(22.642f, 13.028f, 22.642f, 12.238f, 22.153f, 11.748f)
            curveTo(21.663f, 11.257f, 20.872f, 11.257f, 20.382f, 11.748f)
            lineTo(15.962f, 16.167f)
            lineTo(15.252f, 15.458f)
            lineTo(21.792f, 8.917f)
            curveTo(22.282f, 8.427f, 22.282f, 7.637f, 21.792f, 7.148f)
            curveTo(21.302f, 6.657f, 20.513f, 6.657f, 20.022f, 7.148f)
            lineTo(14.193f, 12.977f)
            lineTo(13.483f, 12.267f)
            lineTo(20.372f, 5.378f)
            curveTo(20.862f, 4.887f, 20.862f, 4.097f, 20.372f, 3.608f)
            curveTo(19.882f, 3.118f, 19.093f, 3.118f, 18.603f, 3.608f)
            lineTo(11.712f, 10.498f)
            lineTo(11.023f, 9.797f)
            lineTo(16.503f, 4.318f)
            curveTo(16.993f, 3.828f, 16.993f, 3.037f, 16.503f, 2.547f)
            curveTo(16.013f, 2.057f, 15.222f, 2.057f, 14.733f, 2.547f)
            lineTo(7.113f, 10.167f)
            curveTo(8.333f, 11.738f, 8.222f, 14.007f, 6.782f, 15.448f)
            lineTo(6.073f, 14.738f)
            curveTo(7.242f, 13.568f, 7.242f, 11.667f, 6.073f, 10.498f)
            lineTo(5.722f, 10.148f)
            lineTo(9.792f, 6.077f)
            curveTo(10.283f, 5.588f, 10.283f, 4.798f, 9.792f, 4.307f)
            curveTo(9.292f, 3.828f, 8.502f, 3.828f, 8.012f, 4.318f)
            close()
        }
    }.build()
}
