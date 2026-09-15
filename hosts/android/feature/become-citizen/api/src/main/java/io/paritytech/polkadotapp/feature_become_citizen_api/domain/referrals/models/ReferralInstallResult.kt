package io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models

import android.net.Uri

interface ReferralInstallResult {
    data object NotSupported : ReferralInstallResult
    data object AlreadyHandled : ReferralInstallResult
    data object ServiceUnavailable : ReferralInstallResult
    data object ServiceDisconnected : ReferralInstallResult
    data object BadParams : ReferralInstallResult
    data class DeeplinkExtracted(val deeplink: Uri) : ReferralInstallResult
}
