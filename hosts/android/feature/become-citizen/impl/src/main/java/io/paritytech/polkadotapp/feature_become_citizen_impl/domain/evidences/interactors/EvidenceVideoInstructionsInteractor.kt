package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.interactors

import io.paritytech.polkadotapp.common.data.platform.BatteryService
import io.paritytech.polkadotapp.common.utils.FeatureFlags
import io.paritytech.polkadotapp.common.utils.FeatureOption
import io.paritytech.polkadotapp.common.utils.Fraction.Companion.percents
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage.EvidenceStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.EvidencesStorageConstants
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.models.ProvideEvidencePrecondition
import javax.inject.Inject

class EvidenceVideoInstructionsInteractor @Inject constructor(
    private val batteryService: BatteryService,
    private val storage: EvidenceStorage
) {
    fun checkPreconditions(): ProvideEvidencePrecondition? {
        return checkStorage() ?: checkBattery()
    }

    private fun checkBattery(): ProvideEvidencePrecondition.BatteryTooLow? {
        val required = if (FeatureFlags.isEnabled(FeatureOption.LOW_BATTERY_EVIDENCE_PROVISION))
            0.percents
        else 50.percents

        val currentLevel = batteryService.currentBatteryLevel()

        return if (currentLevel < required)
            ProvideEvidencePrecondition.BatteryTooLow(required)
        else null
    }

    private fun checkStorage(): ProvideEvidencePrecondition.NotEnoughSpace? {
        val required = EvidencesStorageConstants.MIN_TOTAL_STORAGE_REQUIRED
        val free = storage.getFreeStorageSpace()

        return if (free < required) {
            ProvideEvidencePrecondition.NotEnoughSpace(required)
        } else {
            null
        }
    }
}
