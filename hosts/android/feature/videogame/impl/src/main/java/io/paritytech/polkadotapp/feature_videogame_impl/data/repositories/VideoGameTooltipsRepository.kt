package io.paritytech.polkadotapp.feature_videogame_impl.data.repositories

import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import javax.inject.Inject

interface VideoGameTooltipsRepository {
    fun isShowGesturesTooltipShown(): Boolean
    fun isCopyGestureTooltipShown(): Boolean

    fun setShowGestureTooltipShown()
    fun setCopyGestureTooltipShown()
}

internal class RealVideoGameTooltipsRepository @Inject constructor(
    private val preferences: Preferences,
) : VideoGameTooltipsRepository {
    companion object {
        private const val CURRENT_PLAYER_HOST_TOOLTIP = "RealVideoGameTooltipsRepository.CURRENT_PLAYER_HOST_TOOLTIP"
        private const val ANOTHER_PLAYER_HOST_TOOLTIP = "RealVideoGameTooltipsRepository.ANOTHER_PLAYER_HOST_TOOLTIP"
    }

    override fun isShowGesturesTooltipShown(): Boolean {
        return preferences.getBoolean(CURRENT_PLAYER_HOST_TOOLTIP, false)
    }

    override fun isCopyGestureTooltipShown(): Boolean {
        return preferences.getBoolean(ANOTHER_PLAYER_HOST_TOOLTIP, false)
    }

    override fun setShowGestureTooltipShown() {
        return preferences.putBoolean(CURRENT_PLAYER_HOST_TOOLTIP, true)
    }

    override fun setCopyGestureTooltipShown() {
        return preferences.putBoolean(ANOTHER_PLAYER_HOST_TOOLTIP, true)
    }
}
