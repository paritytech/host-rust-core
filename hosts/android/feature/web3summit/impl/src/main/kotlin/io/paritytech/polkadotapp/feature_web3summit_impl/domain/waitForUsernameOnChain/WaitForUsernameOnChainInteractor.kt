package io.paritytech.polkadotapp.feature_web3summit_impl.domain.waitForUsernameOnChain

import io.paritytech.polkadotapp.feature_people_api.domain.PeopleCheckMemberInRingUseCase
import io.paritytech.polkadotapp.feature_people_api.domain.PeopleCollection
import io.paritytech.polkadotapp.feature_web3summit_impl.data.storage.PreferencesLightPersonhoodEstablishedStorage
import javax.inject.Inject

class WaitForUsernameOnChainInteractor @Inject constructor(
    private val peopleCheckMemberInRingUseCase: PeopleCheckMemberInRingUseCase,
    private val lightPersonhoodStorage: PreferencesLightPersonhoodEstablishedStorage,
) {
    suspend fun awaitLightPersonhoodEstablished(): Result<Unit> {
        return peopleCheckMemberInRingUseCase.awaitIncluded(PeopleCollection.LitePeople)
            .onSuccess { lightPersonhoodStorage.setEstablished(true) }
    }
}
