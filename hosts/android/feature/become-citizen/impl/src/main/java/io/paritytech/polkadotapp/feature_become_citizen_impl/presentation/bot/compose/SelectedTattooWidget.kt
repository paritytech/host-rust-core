package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.compose

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImage
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.compose.components.TattooImageItem
import io.paritytech.polkadotapp.feature_chats_api.presentation.common.getMaxMessageWidth

@Composable
fun SelectedTattooWidget(
    name: String,
    tattooImage: TattooImage,
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        VerticalSpacer { small }

        NovaText(
            modifier = Modifier
                .padding(horizontal = PolkadotTheme.spacings.mediumIncreased)
                .fillMaxWidth(),
            text = stringResource(R.string.chat_bot_tattoo_you_ve_commited_to_tattoo, name),
            textAlign = TextAlign.Center,
            color = PolkadotTheme.colors.fg.secondary,
            style = PolkadotTheme.typography.body.medium
        )

        VerticalSpacer { large }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = PolkadotTheme.spacings.mediumIncreased),
            contentAlignment = Alignment.CenterEnd
        ) {
            TattooImageItem(
                modifier = Modifier
                    .width(getMaxMessageWidth())
                    .aspectRatio(1f),
                tattooImage = tattooImage
            )
        }
        VerticalSpacer { small }
    }
}
