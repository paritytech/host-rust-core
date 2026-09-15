package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.icons
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

val DigitalDollarIcon: ImageVector by lazy(LazyThreadSafetyMode.NONE) {
    ImageVector.Builder(
        name = "DigitalDollarIcon",
        defaultWidth = 20.dp,
        defaultHeight = 24.dp,
        viewportWidth = 20f,
        viewportHeight = 24f
    ).apply {
        path(fill = SolidColor(Color.White)) {
            moveTo(13.792f, 23.304f)
            curveTo(9.607f, 23.306f, 6.596f, 23.079f, 3.408f, 19.903f)
            curveTo(1.207f, 17.717f, -0.022f, 14.737f, 0f, 11.634f)
            curveTo(-0.009f, 8.533f, 1.233f, 5.558f, 3.444f, 3.384f)
            curveTo(6.67f, 0.177f, 9.849f, -0.003f, 14.077f, 0f)
            lineTo(19.376f, 0.011f)
            lineTo(19.377f, 0.029f)
            lineTo(19.374f, 0.027f)
            lineTo(19.371f, 7.779f)
            lineTo(19.377f, 7.78f)
            lineTo(19.377f, 7.794f)
            lineTo(19.373f, 7.794f)
            lineTo(19.373f, 7.791f)
            curveTo(17.367f, 7.796f, 15.353f, 7.767f, 13.347f, 7.765f)
            curveTo(11.493f, 7.764f, 10.329f, 7.661f, 8.851f, 8.952f)
            curveTo(7.432f, 10.479f, 7.335f, 12.882f, 8.844f, 14.374f)
            curveTo(9.385f, 14.9f, 10.064f, 15.264f, 10.801f, 15.424f)
            curveTo(11.622f, 15.611f, 15.524f, 15.584f, 17.904f, 15.565f)
            lineTo(17.904f, 15.568f)
            lineTo(19.377f, 15.568f)
            lineTo(19.377f, 23.285f)
            lineTo(19.374f, 23.285f)
            curveTo(19.224f, 23.29f, 19.072f, 23.292f, 18.921f, 23.293f)
            lineTo(13.792f, 23.304f)
            close()
        }
    }.build()
}
