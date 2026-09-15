package io.paritytech.polkadotapp.feature_chats_api.presentation.faq.compose

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.util.fastForEach
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatExtensionId
import io.paritytech.polkadotapp.feature_chats_api.presentation.faq.ChatFaqContract
import io.paritytech.polkadotapp.feature_chats_api.presentation.faq.ChatFaqViewModel
import io.paritytech.polkadotapp.feature_chats_api.presentation.faq.model.FaqQuestion
import io.paritytech.polkadotapp.feature_chats_api.presentation.faq.model.FaqUiState
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun FaqQuestions(
    modifier: Modifier = Modifier,
    botId: ChatExtensionId,
    allQuestions: ImmutableList<FaqQuestion>
) {
    val contract = hiltViewModel<ChatFaqViewModel, ChatFaqViewModel.Factory>(
        creationCallback = { it.create(botId, allQuestions) }
    ) as ChatFaqContract

    val state by contract.state.collectAsStateWithLifecycle()

    FaqQuestionsInternal(
        modifier = modifier,
        state = state,
        onAskQuestion = contract::askQuestion
    )
}

@Composable
private fun FaqQuestionsInternal(
    modifier: Modifier,
    state: FaqUiState,
    onAskQuestion: (FaqQuestion) -> Unit
) {
    Box(modifier) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .animateContentSize(),
            verticalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.small),
            horizontalAlignment = Alignment.End,
        ) {
            state.questions.fastForEach { question ->
                FaqChip(
                    text = stringResource(question.resId),
                    onClick = { onAskQuestion(question) }
                )
            }
        }
    }
}

@Composable
private fun FaqChip(
    text: String,
    onClick: () -> Unit
) {
    PolkadotSurface(
        color = Color.Transparent,
        shape = RoundedCornerShape(
            topStart = 12.dp,
            topEnd = 12.dp,
            bottomStart = 12.dp,
            bottomEnd = 4.dp
        ),
        border = BorderStroke(PolkadotTheme.borders.default, Color(0x1FFFFFFF)),
        onClick = onClick
    ) {
        NovaText(
            modifier = Modifier.padding(
                horizontal = PolkadotTheme.spacings.mediumIncreased,
                vertical = PolkadotTheme.spacings.extraMedium
            ),
            text = text,
            style = PolkadotTheme.typography.body.mediumEmphasized,
            color = PolkadotTheme.colors.fg.secondary
        )
    }
}

@Preview
@Composable
private fun FaqPreview() {
    PolkadotTheme {
        PolkadotSurface {
            FaqQuestionsInternal(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(
                        horizontal = PolkadotTheme.spacings.mediumIncreased
                    ),
                state = FaqUiState(
                    questions = persistentListOf(
                        object : FaqQuestion {
                            override val resId: Int = RCommon.string.chat_faq_proof_of_ink_question_after_submission
                            override val answerResId: Int = 0
                        },
                        object : FaqQuestion {
                            override val resId: Int = RCommon.string.chat_faq_proof_of_ink_question_alter_location
                            override val answerResId: Int = 0
                        },
                    )
                ),
                onAskQuestion = {}
            )
        }
    }
}
