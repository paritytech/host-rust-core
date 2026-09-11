package io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals

interface ReferralApplyUseCase {
    suspend fun hasSavedReferralTicket(): Boolean
    suspend fun applyReferral(): Result<Unit>
}

suspend fun ReferralApplyUseCase.applyReferralIfPresent(): Result<Unit> {
    return if (hasSavedReferralTicket()) {
        applyReferral()
    } else {
        Result.success(Unit)
    }
}
