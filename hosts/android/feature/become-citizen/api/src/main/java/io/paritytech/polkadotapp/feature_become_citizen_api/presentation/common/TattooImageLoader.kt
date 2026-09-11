package io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common

import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooId

interface TattooImageLoader {
    fun getTattooImage(tattooId: TattooId, familyId: ByteArray): TattooImage
}
