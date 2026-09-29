package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.rejected.compose.icons

import androidx.compose.foundation.Image
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.icon.NovaIcons

@Preview
@Composable
private fun VectorPreview() {
    Image(NovaIcons.CredentialsRejected, null)
}

private var _Credentialsrejected: ImageVector? = null

val NovaIcons.CredentialsRejected: ImageVector
    get() {
        if (_Credentialsrejected != null) {
            return _Credentialsrejected!!
        }
        _Credentialsrejected = ImageVector.Builder(
            name = "Credentialsrejected",
            defaultWidth = 72.dp,
            defaultHeight = 72.dp,
            viewportWidth = 72f,
            viewportHeight = 72f
        ).apply {
            path(
                fill = SolidColor(Color(0xFFFF3123)),
                fillAlpha = 1.0f,
                stroke = null,
                strokeAlpha = 1.0f,
                strokeLineWidth = 1.0f,
                strokeLineCap = StrokeCap.Butt,
                strokeLineJoin = StrokeJoin.Miter,
                strokeLineMiter = 1.0f,
                pathFillType = PathFillType.NonZero
            ) {
                moveTo(72f, 36f)
                arcTo(36f, 36f, 0f, isMoreThanHalf = false, isPositiveArc = true, 36f, 72f)
                arcTo(36f, 36f, 0f, isMoreThanHalf = false, isPositiveArc = true, 0f, 36f)
                arcTo(36f, 36f, 0f, isMoreThanHalf = false, isPositiveArc = true, 72f, 36f)
                close()
            }
            path(
                fill = SolidColor(Color(0xFFFFFFFF)),
                fillAlpha = 1.0f,
                stroke = null,
                strokeAlpha = 1.0f,
                strokeLineWidth = 1.0f,
                strokeLineCap = StrokeCap.Butt,
                strokeLineJoin = StrokeJoin.Miter,
                strokeLineMiter = 1.0f,
                pathFillType = PathFillType.EvenOdd
            ) {
                moveTo(47.6328f, 26.1403f)
                curveTo(48.1224f, 25.6506f, 48.1224f, 24.8568f, 47.6328f, 24.3672f)
                curveTo(47.1432f, 23.8776f, 46.3494f, 23.8776f, 45.8597f, 24.3672f)
                lineTo(36f, 34.227f)
                lineTo(26.1403f, 24.3672f)
                curveTo(25.6506f, 23.8776f, 24.8568f, 23.8776f, 24.3672f, 24.3672f)
                curveTo(23.8776f, 24.8568f, 23.8776f, 25.6506f, 24.3672f, 26.1403f)
                lineTo(34.227f, 36f)
                lineTo(24.3672f, 45.8597f)
                curveTo(23.8776f, 46.3494f, 23.8776f, 47.1432f, 24.3672f, 47.6328f)
                curveTo(24.8568f, 48.1224f, 25.6506f, 48.1224f, 26.1403f, 47.6328f)
                lineTo(36f, 37.773f)
                lineTo(45.8598f, 47.6328f)
                curveTo(46.3494f, 48.1224f, 47.1432f, 48.1224f, 47.6328f, 47.6328f)
                curveTo(48.1224f, 47.1432f, 48.1224f, 46.3494f, 47.6328f, 45.8597f)
                lineTo(37.773f, 36f)
                lineTo(47.6328f, 26.1403f)
                close()
            }
        }.build()
        return _Credentialsrejected!!
    }
