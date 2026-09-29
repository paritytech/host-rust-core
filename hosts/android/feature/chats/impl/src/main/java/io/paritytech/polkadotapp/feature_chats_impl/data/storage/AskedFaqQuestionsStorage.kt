package io.paritytech.polkadotapp.feature_chats_impl.data.storage

import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

interface AskedFaqQuestionsStorage {
    fun observeAskedQuestions(botId: String): Flow<Set<Int>>

    fun markQuestionAsAsked(botId: String, questionResId: Int)
}

private const val PREFS_KEY_PREFIX = "AskedFaqQuestions"

class RealAskedFaqQuestionsStorage @Inject constructor(
    private val preferences: Preferences
) : AskedFaqQuestionsStorage {
    override fun observeAskedQuestions(botId: String): Flow<Set<Int>> {
        return preferences.stringSetFlow(createPrefsKey(botId))
            .map { stringSet -> stringSet.mapNotNull { it.toIntOrNull() }.toSet() }
    }

    override fun markQuestionAsAsked(botId: String, questionResId: Int) {
        val key = createPrefsKey(botId)
        val current = preferences.getStringSet(key)
        val updated = current + questionResId.toString()
        preferences.putStringSet(key, updated)
    }

    private fun createPrefsKey(botId: String): String {
        return "$PREFS_KEY_PREFIX.$botId"
    }
}
