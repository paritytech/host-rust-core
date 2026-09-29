package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.overlay

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import javax.inject.Inject
import javax.inject.Singleton

internal interface WeeklyGamePillVisibilityHolder {
    val footerVisible: StateFlow<Boolean>
    val inlinePillVisible: StateFlow<Boolean>

    fun setFooterVisible(visible: Boolean)
    fun setInlinePillVisible(visible: Boolean)
}

@Singleton
internal class RealWeeklyGamePillVisibilityHolder @Inject constructor() : WeeklyGamePillVisibilityHolder {
    override val footerVisible = MutableStateFlow(false)
    override val inlinePillVisible = MutableStateFlow(false)

    override fun setFooterVisible(visible: Boolean) {
        footerVisible.value = visible
    }

    override fun setInlinePillVisible(visible: Boolean) {
        inlinePillVisible.value = visible
    }
}
