package io.paritytech.polkadotapp.feature_wallet_impl.presentation.compose.components.icons
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

val DigitalDollarIcon: ImageVector by lazy(LazyThreadSafetyMode.NONE) {
    ImageVector.Builder(
        name = "DigitalDollarIcon",
        defaultWidth = 21.5.dp,
        defaultHeight = 24.dp,
        viewportWidth = 76f,
        viewportHeight = 85f
    ).apply {
        path(fill = SolidColor(Color.White)) {
            moveTo(42.5f, 0f)
            curveTo(45.4601f, 0f, 48.3494f, 0.3024f, 51.1387f, 0.8784f)
            curveTo(35.7299f, 4.869f, 24.1455f, 21.9875f, 24.1455f, 42.5f)
            lineTo(24.1563f, 43.5968f)
            curveTo(24.5608f, 63.6213f, 36.0071f, 80.2017f, 51.1417f, 84.1196f)
            curveTo(48.3514f, 84.6961f, 45.4612f, 85f, 42.5f, 85f)
            curveTo(19.0279f, 84.9999f, 0f, 65.9721f, 0f, 42.5f)
            curveTo(0f, 19.0278f, 19.0279f, 0.0001f, 42.5f, 0f)
            close()

            moveTo(32.1526f, 61.7113f)
            curveTo(37.7675f, 68.6748f, 46.3674f, 73.1309f, 56.0089f, 73.1309f)
            curveTo(62.5461f, 73.1308f, 68.6047f, 71.0823f, 73.5785f, 67.5928f)
            curveTo(74.5836f, 66.8876f, 76.3457f, 68.2311f, 75.5744f, 69.1863f)
            curveTo(71.649f, 74.0462f, 66.6744f, 78.0229f, 60.9952f, 80.7731f)
            curveTo(60.0127f, 80.9027f, 59.0205f, 80.9699f, 58.0225f, 80.9699f)
            curveTo(47.3857f, 80.9696f, 37.4468f, 73.4569f, 32.1526f, 61.7113f)
            close()

            moveTo(58.0225f, 4.0292f)
            curveTo(59.0195f, 4.0292f, 60.0107f, 4.0956f, 60.9922f, 4.2249f)
            curveTo(66.6726f, 6.9751f, 71.6482f, 10.9521f, 75.5744f, 15.8127f)
            curveTo(76.3459f, 16.7679f, 74.5836f, 18.1114f, 73.5785f, 17.4063f)
            curveTo(68.6046f, 13.917f, 62.5459f, 11.8692f, 56.0089f, 11.8691f)
            curveTo(46.3677f, 11.8691f, 37.7675f, 16.3246f, 32.1526f, 23.2877f)
            curveTo(37.4469f, 11.5421f, 47.3858f, 4.0294f, 58.0225f, 4.0292f)
            close()
        }
    }.build()
}
