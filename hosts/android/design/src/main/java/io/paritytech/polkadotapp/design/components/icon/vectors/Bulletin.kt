package io.paritytech.polkadotapp.design.components.icon.vectors

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.icon.NovaIcons

val NovaIcons.Bulletin: ImageVector by lazy(LazyThreadSafetyMode.NONE) {
    ImageVector.Builder(
        name = "Bulletin",
        defaultWidth = 9.dp,
        defaultHeight = 8.dp,
        viewportWidth = 9f,
        viewportHeight = 8f
    ).apply {
        path(fill = SolidColor(Color(0xFF000000))) {
            moveTo(0f, 0f)
            horizontalLineTo(2.5896f)
            lineTo(3.6409f, 1.2846f)
            horizontalLineTo(8.1387f)
            verticalLineTo(7.0488f)
            horizontalLineTo(0f)
            verticalLineTo(0f)
            close()
        }
    }.build()
}

@Preview(showBackground = true)
@Composable
private fun BulletinPreview() {
    Box(modifier = Modifier.padding(12.dp)) {
        Image(imageVector = NovaIcons.Bulletin, contentDescription = null)
    }
}
