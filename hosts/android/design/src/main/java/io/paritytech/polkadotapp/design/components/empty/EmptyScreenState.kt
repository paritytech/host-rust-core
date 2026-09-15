package io.paritytech.polkadotapp.design.components.empty

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme

@Composable
fun EmptyScreenState(title: String, message: String) {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        NovaText(
            text = title,
            style = PolkadotTheme.typography.title.medium,
            color = PolkadotTheme.colors.fg.primary
        )
        VerticalSpacer { extraMedium }
        NovaText(
            text = message,
            style = PolkadotTheme.typography.body.medium,
            color = PolkadotTheme.colors.fg.tertiary,
            textAlign = TextAlign.Center
        )
    }
}

@Preview(backgroundColor = 0xFF191919, showBackground = true)
@Composable
private fun EmptyScreenStatePreview() {
    PolkadotTheme {
        EmptyScreenState(
            "No Active Chats",
            "Start a conversation with someone using\ntheir username like andrey.99"
        )
    }
}
