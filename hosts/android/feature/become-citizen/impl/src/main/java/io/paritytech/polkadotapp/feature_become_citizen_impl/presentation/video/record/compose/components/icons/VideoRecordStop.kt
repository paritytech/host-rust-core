package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.record.compose.components.icons

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

val VideoRecordStop: ImageVector by lazy(LazyThreadSafetyMode.NONE) {
    ImageVector.Builder(
        name = "VideoRecordStop",
        defaultWidth = 82.dp,
        defaultHeight = 82.dp,
        viewportWidth = 82f,
        viewportHeight = 82f
    ).apply {
        path(fill = SolidColor(Color(0xFFE6007A))) {
            moveTo(32.37f, 23.74f)
            lineTo(49.63f, 23.74f)
            arcTo(8.63f, 8.63f, 0.0f, false, true, 58.26f, 32.37f)
            lineTo(58.26f, 49.63f)
            arcTo(8.63f, 8.63f, 0.0f, false, true, 49.63f, 58.26f)
            lineTo(32.37f, 58.26f)
            arcTo(8.63f, 8.63f, 0.0f, false, true, 23.74f, 49.63f)
            lineTo(23.74f, 32.37f)
            arcTo(8.63f, 8.63f, 0.0f, false, true, 32.37f, 23.74f)
            close()
        }
        path(
            fill = null,
            stroke = SolidColor(Color.White),
            strokeLineWidth = 4.315f
        ) {
            moveTo(41.0f, 41.0f)
            moveToRelative(-38.84f, 0.0f)
            arcToRelative(38.84f, 38.84f, 0.0f, true, true, 77.68f, 0.0f)
            arcToRelative(38.84f, 38.84f, 0.0f, true, true, -77.68f, 0.0f)
        }
    }.build()
}
