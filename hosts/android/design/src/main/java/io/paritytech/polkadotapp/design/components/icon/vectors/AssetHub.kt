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

val NovaIcons.AssetHub: ImageVector by lazy(LazyThreadSafetyMode.NONE) {
    ImageVector.Builder(
        name = "AssetHub",
        defaultWidth = 10.dp,
        defaultHeight = 10.dp,
        viewportWidth = 10f,
        viewportHeight = 10f
    ).apply {
        path(fill = SolidColor(Color(0xFF000000))) {
            moveTo(7.617f, 4.769f)
            curveTo(6.301f, 4.768f, 5.234f, 3.701f, 5.233f, 2.385f)
            curveTo(5.233f, 1.068f, 6.301f, 0f, 7.617f, -0f)
            curveTo(8.934f, -0f, 10.002f, 1.068f, 10.002f, 2.385f)
            curveTo(10.002f, 3.701f, 8.934f, 4.769f, 7.617f, 4.769f)
            close()
            moveTo(2.691f, 0.103f)
            lineTo(5.383f, 4.764f)
            lineTo(0f, 4.764f)
            lineTo(2.691f, 0.103f)
            close()
            moveTo(3.03f, 5.53f)
            lineTo(7.237f, 5.53f)
            lineTo(7.237f, 9.737f)
            lineTo(3.03f, 9.737f)
            lineTo(3.03f, 5.53f)
            close()
        }
    }.build()
}

@Preview(showBackground = true)
@Composable
private fun AssetHubPreview() {
    Box(modifier = Modifier.padding(12.dp)) {
        Image(imageVector = NovaIcons.AssetHub, contentDescription = null)
    }
}
