package io.paritytech.polkadotapp.feature_become_citizen_api.domain.models

import kotlin.time.Duration

class TattooDetails(
    val familyMetadata: TattooFamilyMetadata,
    val reviewTime: ReviewTime?
) {
    class ReviewTime(val from: Duration, val to: Duration)
}
