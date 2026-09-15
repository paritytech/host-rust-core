package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.compose.components.icons

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

val RecordStart: ImageVector by lazy(LazyThreadSafetyMode.NONE) {
    ImageVector.Builder(
        name = "RecordStart",
        defaultWidth = 82.dp,
        defaultHeight = 82.dp,
        viewportWidth = 82f,
        viewportHeight = 82f
    ).apply {
        path(fill = SolidColor(Color(0xFFE6007A))) {
            moveTo(41f, 41f)
            moveToRelative(-32f, 0f)
            arcToRelative(32f, 32f, 0f, isMoreThanHalf = true, isPositiveArc = true, 64f, 0f)
            arcToRelative(32f, 32f, 0f, isMoreThanHalf = true, isPositiveArc = true, -64f, 0f)
        }
        path(
            stroke = SolidColor(Color.White),
            strokeLineWidth = 7f
        ) {
            moveTo(41f, 41f)
            moveToRelative(-37.5f, 0f)
            arcToRelative(37.5f, 37.5f, 0f, isMoreThanHalf = true, isPositiveArc = true, 75f, 0f)
            arcToRelative(37.5f, 37.5f, 0f, isMoreThanHalf = true, isPositiveArc = true, -75f, 0f)
        }
    }.build()
}
