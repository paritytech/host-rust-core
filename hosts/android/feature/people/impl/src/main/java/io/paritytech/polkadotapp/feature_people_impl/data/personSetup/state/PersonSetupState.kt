package io.paritytech.polkadotapp.feature_people_impl.data.personSetup.state

import io.paritytech.polkadotapp.common.data.worker.stateMachine.WorkerStateMachineState
import io.paritytech.polkadotapp.feature_people_impl.data.personSetup.PersonSetupDataSource

sealed interface PersonSetupState : WorkerStateMachineState<PersonSetupState, PersonSetupState.Transition> {
    interface Transition {
        val dataSource: PersonSetupDataSource
    }
}
