package io.paritytech.polkadotapp.feature_people_impl.domain.useCase

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonhoodStatus
import io.paritytech.polkadotapp.feature_people_api.domain.useCase.PersonStatusUseCase
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import javax.inject.Inject

class DisabledPersonStatusUseCase @Inject constructor() : PersonStatusUseCase {
    override fun personhoodStatusFlow(): Flow<PersonhoodStatus> {
        return flowOf(PersonhoodStatus.NotPerson)
    }

    override fun canUseAliasFlow(context: BandersnatchContext): Flow<Boolean> {
        return flowOf(false)
    }

    override fun personhoodAccountsFullySetFlow(): Flow<Boolean> {
        return flowOf(false)
    }
}
