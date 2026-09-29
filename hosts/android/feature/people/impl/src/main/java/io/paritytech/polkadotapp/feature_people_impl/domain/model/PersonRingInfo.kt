package io.paritytech.polkadotapp.feature_people_impl.domain.model

import io.paritytech.polkadotapp.feature_members_api.data.model.RingIndex
import io.paritytech.polkadotapp.feature_members_api.data.model.RingStatus

class PersonRingInfo(
    val ringIndex: RingIndex,
    val ringStatus: RingStatus
)
