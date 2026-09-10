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

val NovaIcons.People: ImageVector by lazy(LazyThreadSafetyMode.NONE) {
    ImageVector.Builder(
        name = "People",
        defaultWidth = 9.dp,
        defaultHeight = 10.dp,
        viewportWidth = 9f,
        viewportHeight = 10f
    ).apply {
        path(fill = SolidColor(Color(0xFF000000))) {
            moveTo(8.171f, 9.25f)
            horizontalLineTo(0f)
            verticalLineTo(5.194f)
            horizontalLineTo(8.171f)
            verticalLineTo(9.25f)
            close()
            moveTo(4.085f, 0f)
            curveTo(5.354f, 0f, 6.382f, 1.028f, 6.382f, 2.297f)
            curveTo(6.382f, 3.565f, 5.353f, 4.594f, 4.085f, 4.594f)
            curveTo(2.817f, 4.594f, 1.788f, 3.565f, 1.788f, 2.297f)
            curveTo(1.788f, 1.028f, 2.817f, 0f, 4.085f, 0f)
            close()
        }
    }.build()
}

@Preview(showBackground = true)
@Composable
private fun PeoplePreview() {
    Box(modifier = Modifier.padding(12.dp)) {
        Image(imageVector = NovaIcons.People, contentDescription = null)
    }
}
