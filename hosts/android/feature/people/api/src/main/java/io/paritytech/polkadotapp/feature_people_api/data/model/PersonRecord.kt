package io.paritytech.polkadotapp.feature_people_api.data.model

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import kotlinx.serialization.Serializable

@Serializable
class PersonRecord(
    val key: DataByteArray,
    val account: AccountId?
)
