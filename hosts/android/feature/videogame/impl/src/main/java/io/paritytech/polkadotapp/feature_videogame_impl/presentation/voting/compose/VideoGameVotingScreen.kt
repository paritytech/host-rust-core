package io.paritytech.polkadotapp.feature_videogame_impl.presentation.voting.compose

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.components.DiagonalStripeBackground
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.GameColors
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.voting.VideoGameVotingContract
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.voting.compose.components.Footer
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.voting.compose.components.Header
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.voting.compose.components.PlayerVotingCell
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.voting.models.PlayerVotingUiModel
import kotlinx.collections.immutable.ImmutableList

private const val GridColumns = 2

@Composable
fun VideoGameVotingScreen(contract: VideoGameVotingContract) {
    VideoGameVotingScreenInternal(
        players = contract.players.collectAsStateWithLifecycle().value,
        inProgress = contract.inProgress.collectAsStateWithLifecycle().value,
        autoConfirm = contract.autoConfirm.collectAsStateWithLifecycle().value,
        onPlayerVoteToggle = contract::togglePlayerVote,
        onDone = contract::confirm
    )
}

@Composable
private fun VideoGameVotingScreenInternal(
    players: ImmutableList<PlayerVotingUiModel>,
    inProgress: Boolean,
    autoConfirm: Boolean,
    onPlayerVoteToggle: (PlayerVotingUiModel) -> Unit,
    onDone: () -> Unit
) {
    val density = LocalDensity.current

    PolkadotSurface(
        modifier = Modifier.fillMaxSize(),
        color = GameColors.backgroundPrimary
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            DiagonalStripeBackground(
                modifier = Modifier.fillMaxSize(),
                isVisible = true
            )

            var footerHeight by remember { mutableStateOf(0.dp) }

            LazyVerticalGrid(
                modifier = Modifier.fillMaxSize(),
                columns = GridCells.Fixed(GridColumns),
                contentPadding = PaddingValues(
                    start = PolkadotTheme.spacings.small,
                    end = PolkadotTheme.spacings.small,
                    bottom = footerHeight + PolkadotTheme.spacings.mediumIncreased
                ),
                verticalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.mediumIncreased),
                horizontalArrangement = Arrangement.spacedBy(
                    PolkadotTheme.spacings.small,
                    Alignment.CenterHorizontally
                )
            ) {
                item(
                    span = { GridItemSpan(GridColumns) }
                ) {
                    Header()
                }

                val cellModifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(1f)

                items(
                    items = players,
                    key = { it.accountId.toString() }
                ) {
                    PlayerVotingCell(
                        modifier = cellModifier,
                        player = it,
                        onClick = { onPlayerVoteToggle(it) },
                        enabled = inProgress.not()
                    )
                }
            }

            Footer(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .navigationBarsPadding()
                    .onSizeChanged {
                        footerHeight = with(density) { it.height.toDp() }
                    },
                onDone = onDone,
                inProgress = inProgress,
                autoConfirm = autoConfirm
            )
        }
    }
}
