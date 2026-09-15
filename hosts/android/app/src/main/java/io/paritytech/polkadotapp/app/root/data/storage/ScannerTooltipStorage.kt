package io.paritytech.polkadotapp.app.root.data.storage

import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import javax.inject.Inject

class ScannerTooltipStorage @Inject constructor(
    private val preferences: Preferences
) {
    fun wasShown(): Boolean = preferences.getBoolean(KEY_SCANNER_TOOLTIP_SHOWN, false)

    fun markShown() {
        preferences.putBoolean(KEY_SCANNER_TOOLTIP_SHOWN, true)
    }

    companion object {
        private const val KEY_SCANNER_TOOLTIP_SHOWN = "scanner_tooltip_shown"
    }
}
