package io.paritytech.polkadotapp.feature_people_impl.data.personSetup.state

import io.paritytech.polkadotapp.common.data.worker.stateMachine.error.TransitionDidNotSucceedException
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import io.paritytech.polkadotapp.feature_people_impl.data.personSetup.awaitPersonId
import io.paritytech.polkadotapp.feature_people_impl.data.storage.PersonIdStorage

class AwaitRingInclusionState(
    private val personIdStorage: PersonIdStorage,
    private val stateFactory: PersonSetupStateFactory,
) : PersonSetupNonTerminalState() {
    companion object {
        val ID = "AwaitRingInclusion"
    }

    override val id = ID

    context(transition: PersonSetupState.Transition)
    override suspend fun performNonTerminalTransition(): Result<PersonSetupState> = runCatching {
        val personId = awaitAssignedPersonId()
        // This is needed because PersonIdUpdater cannot sync personId while the app is in background
        personIdStorage.savePersonId(personId)

        if (transition.dataSource.hasIncludedIntoRing()) {
            stateFactory.setAliasState(SetAliasState.Params.initial())
        } else {
            throw TransitionDidNotSucceedException("Not yet included into ring")
        }
    }

    context(transition: PersonSetupState.Transition)
    private suspend fun awaitAssignedPersonId(): PersonId {
        return transition.dataSource.subscriptions.await().people.awaitPersonId()
    }
}
