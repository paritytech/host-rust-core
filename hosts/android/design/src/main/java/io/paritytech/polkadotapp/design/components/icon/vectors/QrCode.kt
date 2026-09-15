package io.paritytech.polkadotapp.design.components.icon.vectors

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.icon.NovaIcons

val NovaIcons.QrCode: ImageVector by lazy(LazyThreadSafetyMode.NONE) {
    ImageVector.Builder(
        name = "QrCode",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f
    ).apply {
        path(
            stroke = SolidColor(Color(0xFF808B93)),
            strokeLineWidth = 2f,
            strokeLineCap = StrokeCap.Round,
            strokeLineJoin = StrokeJoin.Round
        ) {
            moveTo(21f, 16f)
            horizontalLineTo(18f)
            curveTo(17.47f, 16f, 16.961f, 16.211f, 16.586f, 16.586f)
            curveTo(16.211f, 16.961f, 16f, 17.47f, 16f, 18f)
            verticalLineTo(21f)
            moveTo(21f, 21f)
            verticalLineTo(21.01f)
            moveTo(12f, 7f)
            verticalLineTo(10f)
            curveTo(12f, 10.53f, 11.789f, 11.039f, 11.414f, 11.414f)
            curveTo(11.039f, 11.789f, 10.53f, 12f, 10f, 12f)
            horizontalLineTo(7f)
            moveTo(3f, 12f)
            horizontalLineTo(3.01f)
            moveTo(12f, 3f)
            horizontalLineTo(12.01f)
            moveTo(12f, 16f)
            verticalLineTo(16.01f)
            moveTo(16f, 12f)
            horizontalLineTo(17f)
            moveTo(21f, 12f)
            verticalLineTo(12.01f)
            moveTo(12f, 21f)
            verticalLineTo(20f)
            moveTo(4f, 3f)
            horizontalLineTo(7f)
            curveTo(7.552f, 3f, 8f, 3.448f, 8f, 4f)
            verticalLineTo(7f)
            curveTo(8f, 7.552f, 7.552f, 8f, 7f, 8f)
            horizontalLineTo(4f)
            curveTo(3.448f, 8f, 3f, 7.552f, 3f, 7f)
            verticalLineTo(4f)
            curveTo(3f, 3.448f, 3.448f, 3f, 4f, 3f)
            close()
            moveTo(17f, 3f)
            horizontalLineTo(20f)
            curveTo(20.552f, 3f, 21f, 3.448f, 21f, 4f)
            verticalLineTo(7f)
            curveTo(21f, 7.552f, 20.552f, 8f, 20f, 8f)
            horizontalLineTo(17f)
            curveTo(16.448f, 8f, 16f, 7.552f, 16f, 7f)
            verticalLineTo(4f)
            curveTo(16f, 3.448f, 16.448f, 3f, 17f, 3f)
            close()
            moveTo(4f, 16f)
            horizontalLineTo(7f)
            curveTo(7.552f, 16f, 8f, 16.448f, 8f, 17f)
            verticalLineTo(20f)
            curveTo(8f, 20.552f, 7.552f, 21f, 7f, 21f)
            horizontalLineTo(4f)
            curveTo(3.448f, 21f, 3f, 20.552f, 3f, 20f)
            verticalLineTo(17f)
            curveTo(3f, 16.448f, 3.448f, 16f, 4f, 16f)
            close()
        }
    }.build()
}
