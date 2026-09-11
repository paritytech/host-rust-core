package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.id

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_wallet_impl.R
import io.paritytech.polkadotapp.feature_wallet_impl.domain.model.PocketRank
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.animation.LocalCardTilt
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.animation.holographicSurface
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.CardSizes
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.PocketCardColors
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models.PocketCardUiModel
import io.paritytech.polkadotapp.common.R as RCommon

private val MemberBorderBrush = Brush.verticalGradient(
    listOf(PocketCardColors.Primary, PocketCardColors.MemberBorderBottom)
)

// Card base, painted behind the holographic surface (visible only during sensor warmup).
private val CardBaseColor = Color(0xFF1A1A22)

@Composable
internal fun MemberIdCard(
    modifier: Modifier,
    card: PocketCardUiModel.IdCard,
    onSelected: ((PocketCardUiModel.IdCard) -> Unit)?,
    onQrClick: () -> Unit
) {
    // Read the tilt State in the draw phase (inside the holographic draw lambdas), not via `by` at
    // composition, so per-frame sensor updates don't recompose the card + its content.
    val tiltState = LocalCardTilt.current

    BoxWithConstraints(
        modifier = modifier
            .fillMaxWidth()
            .height(CardSizes.HEIGHT)
            .clip(PolkadotTheme.shapes.large)
            .clickable(
                enabled = onSelected != null,
                onClick = { onSelected?.invoke(card) }
            )
            .background(CardBaseColor)
            .border(
                BorderStroke(PolkadotTheme.borders.default, MemberBorderBrush),
                PolkadotTheme.shapes.large
            )
    ) {
        // Holographic foil surface: the gyroscope-driven shader is the whole card background.
        Box(
            modifier = Modifier
                .matchParentSize()
                .holographicSurface(tiltState)
        )

        val cardWidth = maxWidth
        val cardHeight = maxHeight

        // Wordmark: the same foil fed the lagged tilt, so it trails the background by a beat.
        Box(modifier = Modifier.matchParentSize()) {
            HolographicWordmark(
                cardWidth = cardWidth,
                cardHeight = cardHeight,
                tiltState = tiltState
            )
        }

        IdCardContent(
            username = card.username,
            avatarPainter = painterResource(R.drawable.member_card_avatar_placeholder),
            rankValue = stringResource(RCommon.string.identity_card_rank_member),
            primaryTextColor = PocketCardColors.PrimaryInverted,
            secondaryTextColor = PocketCardColors.SecondaryInverted,
            onQrClick = onQrClick
        )
    }
}

@Preview
@Composable
private fun MemberIdCardPreview() {
    PolkadotTheme {
        IdCard(card = PocketCardUiModel.IdCard("username.99", "15oF4u...zaC1Ap", PocketRank.Member))
    }
}
