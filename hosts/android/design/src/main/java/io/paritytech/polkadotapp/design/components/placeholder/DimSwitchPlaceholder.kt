package io.paritytech.polkadotapp.design.components.placeholder

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonStyle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme

@Composable
fun DimSwitchPlaceholder(
    text: String,
    buttonText: String,
    onEditClick: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(PolkadotTheme.spacings.extraLarge),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        NovaText(
            text = text,
            style = PolkadotTheme.typography.body.medium,
            color = PolkadotTheme.colors.fg.secondary,
            textAlign = TextAlign.Center
        )

        VerticalSpacer { large }

        PolkadotTextButton(
            text = buttonText,
            style = PolkadotButtonStyle.secondary(),
            onClick = onEditClick
        )
    }
}

@Preview
@Composable
private fun DimSwitchPlaceholderPreview() {
    PolkadotTheme {
        DimSwitchPlaceholder(
            text = "You're committed to another DIM. Press \"Edit\" to switch.",
            buttonText = "Edit",
            onEditClick = {}
        )
    }
}
