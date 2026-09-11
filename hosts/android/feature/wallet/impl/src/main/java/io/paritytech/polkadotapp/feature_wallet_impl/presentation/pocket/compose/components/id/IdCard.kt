@file:OptIn(ExperimentalMaterial3Api::class)

package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.id

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.bottomsheet.NovaModalBottomSheet
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_wallet_impl.domain.model.PocketRank
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.IdDetailsBottomSheetContent
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models.PocketCardUiModel

@Composable
fun IdCard(
    modifier: Modifier = Modifier,
    card: PocketCardUiModel.IdCard,
    onSelected: ((PocketCardUiModel.IdCard) -> Unit)? = null,
) {
    var qrDetailsVisible by remember { mutableStateOf(false) }
    when (card.rank) {
        PocketRank.Basic -> BasicIdCard(modifier, card, onSelected) { qrDetailsVisible = true }
        PocketRank.Member -> MemberIdCard(modifier, card, onSelected) { qrDetailsVisible = true }
    }

    NovaModalBottomSheet(
        isVisible = qrDetailsVisible,
        onDismissRequest = { qrDetailsVisible = false }
    ) {
        IdDetailsBottomSheetContent(
            username = card.username,
            address = card.address,
            onClose = { qrDetailsVisible = false }
        )
    }
}

@Preview
@Composable
private fun IdCardPreview() {
    PolkadotTheme {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            IdCard(card = PocketCardUiModel.IdCard("username.99", "15oF4u...zaC1Ap", PocketRank.Basic))
            IdCard(card = PocketCardUiModel.IdCard("username.99", "15oF4u...zaC1Ap", PocketRank.Member))
        }
    }
}
