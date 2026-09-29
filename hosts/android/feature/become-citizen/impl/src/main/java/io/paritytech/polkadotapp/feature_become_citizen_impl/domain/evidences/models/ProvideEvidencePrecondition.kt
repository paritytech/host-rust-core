package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.models

import androidx.compose.runtime.Immutable
import io.paritytech.polkadotapp.common.utils.Fraction
import io.paritytech.polkadotapp.common.utils.InformationSize

@Immutable
sealed class ProvideEvidencePrecondition {
    data class NotEnoughSpace(val requiredSpace: InformationSize) : ProvideEvidencePrecondition()
    data class BatteryTooLow(val minimumLevel: Fraction) : ProvideEvidencePrecondition()
}
