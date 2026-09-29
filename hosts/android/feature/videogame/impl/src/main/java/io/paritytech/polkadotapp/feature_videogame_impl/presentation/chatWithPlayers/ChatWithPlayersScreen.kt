package io.paritytech.polkadotapp.feature_videogame_impl.presentation.chatWithPlayers

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.common.presentation.loading.LoadingState
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonStyle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotButtonSize
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.image.NovaAsyncImage
import io.paritytech.polkadotapp.design.components.progress.LoadingScreenState
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.components.topbar.PolkadotTopBar
import io.paritytech.polkadotapp.design.components.topbar.TopBarTitleAlignment
import io.paritytech.polkadotapp.design.components.topbar.rememberTopBarAction
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.chatWithPlayers.models.ContactStatus
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.chatWithPlayers.models.GamePlayerUiModel
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.chatWithPlayers.models.PlayerAction
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.toImmutableList

private val AVATAR_SIZE = 81.dp
private val BUTTON_MIN_SIZE = 88.dp

@Composable
fun ChatWithPlayersScreen(viewModel: ChatWithPlayersViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsStateWithLifecycle()

    ChatWithPlayersContent(
        state = state,
        onPlayerAction = viewModel::onPlayerAction,
        onBackClick = viewModel::onBackClick
    )
}

@Composable
private fun ChatWithPlayersContent(
    state: LoadingState<List<GamePlayerUiModel>>,
    onPlayerAction: (GamePlayerUiModel, PlayerAction) -> Unit,
    onBackClick: () -> Unit
) {
    PolkadotSurface {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .systemBarsPadding()
        ) {
            PolkadotTopBar(
                title = stringResource(R.string.video_game_chat_with_players_title),
                navigationAction = rememberTopBarAction(onBackClick),
                titleAlignment = TopBarTitleAlignment.Center,
            )

            when (state) {
                is LoadingState.Loading -> LoadingScreenState()
                is LoadingState.Error -> Unit
                is LoadingState.Loaded -> PlayersContent(
                    players = state.data.toImmutableList(),
                    onPlayerAction = onPlayerAction
                )
            }
        }
    }
}

@Composable
private fun PlayersContent(
    players: ImmutableList<GamePlayerUiModel>,
    onPlayerAction: (GamePlayerUiModel, PlayerAction) -> Unit
) {
    if (players.isEmpty()) {
        EmptyPlayersContent()
    } else {
        PlayersGrid(
            players = players,
            onPlayerAction = onPlayerAction
        )
    }
}

@Composable
private fun EmptyPlayersContent() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        NovaText(
            text = stringResource(R.string.video_game_chat_with_players_empty),
            style = PolkadotTheme.typography.body.large,
            color = PolkadotTheme.colors.fg.secondary,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun PlayersGrid(
    players: ImmutableList<GamePlayerUiModel>,
    onPlayerAction: (GamePlayerUiModel, PlayerAction) -> Unit
) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(3),
        modifier = Modifier
            .fillMaxSize()
            .padding(vertical = PolkadotTheme.spacings.mediumIncreased),
        contentPadding = PaddingValues(horizontal = PolkadotTheme.spacings.mediumIncreased),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        items(players, key = { it.accountId.value.contentToString() }) { player ->
            PlayerCard(
                player = player,
                onAction = { action -> onPlayerAction(player, action) }
            )
        }
    }
}

@Composable
private fun PlayerCard(
    player: GamePlayerUiModel,
    onAction: (PlayerAction) -> Unit
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        VerticalSpacer { extraMedium }

        PlayerAvatar(avatarUri = player.avatarUri)

        VerticalSpacer { small }

        when (player.contactStatus) {
            ContactStatus.ADDED -> {
                PolkadotTextButton(
                    modifier = Modifier.widthIn(min = BUTTON_MIN_SIZE),
                    text = stringResource(R.string.video_game_chat_with_players_message),
                    style = PolkadotButtonStyle.primary(),
                    size = PolkadotButtonSize.medium(),
                    onClick = { onAction(PlayerAction.MESSAGE) }
                )
            }
            ContactStatus.NOT_ADDED, ContactStatus.ADDING -> {
                PolkadotTextButton(
                    modifier = Modifier.widthIn(min = BUTTON_MIN_SIZE),
                    text = stringResource(R.string.video_game_chat_with_players_add),
                    style = PolkadotButtonStyle.secondary(),
                    size = PolkadotButtonSize.medium(),
                    loading = player.contactStatus == ContactStatus.ADDING,
                    onClick = { onAction(PlayerAction.ADD) }
                )
            }
        }

        VerticalSpacer { extraMedium }
    }
}

@Composable
private fun PlayerAvatar(avatarUri: String?) {
    NovaAsyncImage(
        model = avatarUri,
        contentDescription = null,
        modifier = Modifier
            .size(AVATAR_SIZE)
            .clip(PolkadotTheme.shapes.full)
            .background(PolkadotTheme.colors.bg.surface.container),
        contentScale = ContentScale.Crop
    )
}

@Preview
@Composable
private fun ChatWithPlayersContentPreview() {
    val mockPlayers = listOf(
        GamePlayerUiModel(
            accountId = DataByteArray(byteArrayOf(1, 2, 3)),
            displayName = "Brave Beaver",
            avatarUri = null,
            contactStatus = ContactStatus.NOT_ADDED
        ),
        GamePlayerUiModel(
            accountId = DataByteArray(byteArrayOf(4, 5, 6)),
            displayName = "Swift Falcon",
            avatarUri = null,
            contactStatus = ContactStatus.ADDED
        ),
        GamePlayerUiModel(
            accountId = DataByteArray(byteArrayOf(7, 8, 9)),
            displayName = "Clever Fox",
            avatarUri = null,
            contactStatus = ContactStatus.NOT_ADDED
        ),
        GamePlayerUiModel(
            accountId = DataByteArray(byteArrayOf(10, 11, 12)),
            displayName = "Happy Hippo",
            avatarUri = null,
            contactStatus = ContactStatus.ADDED
        ),
        GamePlayerUiModel(
            accountId = DataByteArray(byteArrayOf(13, 14, 15)),
            displayName = "Lazy Lion",
            avatarUri = null,
            contactStatus = ContactStatus.ADDING
        ),
        GamePlayerUiModel(
            accountId = DataByteArray(byteArrayOf(16, 17, 18)),
            displayName = "Quick Quail",
            avatarUri = null,
            contactStatus = ContactStatus.ADDED
        )
    )

    PolkadotTheme {
        ChatWithPlayersContent(
            state = LoadingState.Loaded(mockPlayers),
            onPlayerAction = { _, _ -> },
            onBackClick = {}
        )
    }
}

@Preview
@Composable
private fun ChatWithPlayersEmptyPreview() {
    PolkadotTheme {
        ChatWithPlayersContent(
            state = LoadingState.Loaded(emptyList()),
            onPlayerAction = { _, _ -> },
            onBackClick = {}
        )
    }
}

@Preview
@Composable
private fun ChatWithPlayersLoadingPreview() {
    PolkadotTheme {
        ChatWithPlayersContent(
            state = LoadingState.Loading,
            onPlayerAction = { _, _ -> },
            onBackClick = {}
        )
    }
}
