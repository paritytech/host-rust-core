package io.paritytech.polkadotapp.feature_people_api.domain.useCase

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonhoodStatus
import io.paritytech.polkadotapp.feature_people_api.domain.models.isActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first

interface PersonStatusUseCase {
    fun personhoodStatusFlow(): Flow<PersonhoodStatus>

    fun canUseAliasFlow(context: BandersnatchContext): Flow<Boolean>

    fun personhoodAccountsFullySetFlow(): Flow<Boolean>
}

suspend fun PersonStatusUseCase.isPersonhoodActive(): Boolean {
    return personhoodStatusFlow().first().isActive()
}
