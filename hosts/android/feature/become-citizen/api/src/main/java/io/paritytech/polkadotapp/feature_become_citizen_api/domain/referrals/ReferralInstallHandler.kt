package io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals

import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models.ReferralInstallResult

interface ReferralInstallHandler {
    suspend fun getResult(): ReferralInstallResult
}
