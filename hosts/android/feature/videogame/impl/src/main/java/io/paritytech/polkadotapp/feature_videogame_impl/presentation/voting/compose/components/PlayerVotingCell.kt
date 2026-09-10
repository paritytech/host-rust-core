package io.paritytech.polkadotapp.feature_videogame_impl.presentation.voting.compose.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.common.domain.model.intoAccountId
import io.paritytech.polkadotapp.design.components.image.NovaAsyncImage
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.GameColors
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.icons.SelectionNegative
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.icons.SelectionPositive
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.voting.models.PlayerVotingUiModel

@Composable
fun PlayerVotingCell(
    modifier: Modifier = Modifier,
    player: PlayerVotingUiModel,
    onClick: () -> Unit,
    enabled: Boolean
) {
    Box(modifier = modifier) {
        PolkadotSurface(
            modifier = Modifier.fillMaxSize(),
            color = GameColors.playerFrameBackground,
            shape = RoundedCornerShape(VoteCardCornerRadius),
            border = BorderStroke(VoteCardBorderWidth, voteColor(player.isPerson)),
            onClick = onClick,
            enabled = enabled
        ) {
            Box {
                if (player.picture.isNotBlank()) {
                    NovaAsyncImage(
                        modifier = Modifier.fillMaxSize(),
                        model = player.picture,
                        contentScale = ContentScale.Crop
                    )
                }

                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(voteColor(player.isPerson).copy(alpha = VoteOverlayAlpha))
                )

                Image(
                    modifier = Modifier
                        .align(Alignment.Center)
                        .size(VoteStatusIconSize),
                    imageVector = if (player.isPerson) SelectionPositive else SelectionNegative,
                    contentDescription = null
                )
            }
        }
    }
}

private fun voteColor(isPerson: Boolean) = when (isPerson) {
    true -> GameColors.selectionPositive
    false -> GameColors.selectionNegative
}

private val VoteCardCornerRadius = 24.dp
private val VoteCardBorderWidth = 6.dp
private val VoteStatusIconSize = 112.dp
private const val VoteOverlayAlpha = 0.3f

@Preview
@Composable
private fun PlayerVotingCellPreview() {
    PolkadotTheme {
        var vote by remember { mutableStateOf(true) }

        PlayerVotingCell(
            modifier = Modifier.size(180.dp),
            player = PlayerVotingUiModel(
                accountId = "accountId".toByteArray().intoAccountId(),
                picture = "https://img.freepik.com/premium-photo/yellow-smiling-face-icon-png-cute-crayon-shape-transparent-background_53876-995090.jpg?semt=ais_hybrid&w=740",
                isPerson = vote
            ),
            onClick = {
                vote = !vote
            },
            enabled = true
        )
    }
}
