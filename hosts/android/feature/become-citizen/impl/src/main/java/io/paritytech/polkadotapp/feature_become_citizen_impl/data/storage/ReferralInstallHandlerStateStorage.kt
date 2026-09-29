package io.paritytech.polkadotapp.feature_become_citizen_impl.data.storage

import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import javax.inject.Inject

interface ReferralInstallHandlerStorage {
    fun isHandled(): Boolean
    fun setHandled(isHandled: Boolean)
}

private const val INSTALL_REFERRER_KEY = "InstallReferrerHandle.Key"
private const val INSTALL_REFERRER_DEFAULT = false

class RealReferralInstallHandlerStorage @Inject constructor(
    private val preferences: Preferences
) : ReferralInstallHandlerStorage {
    override fun isHandled() = preferences.getBoolean(INSTALL_REFERRER_KEY, INSTALL_REFERRER_DEFAULT)

    override fun setHandled(isHandled: Boolean) {
        preferences.putBoolean(INSTALL_REFERRER_KEY, isHandled)
    }
}
