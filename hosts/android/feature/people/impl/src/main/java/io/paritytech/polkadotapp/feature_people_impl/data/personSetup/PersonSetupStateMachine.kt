package io.paritytech.polkadotapp.feature_people_impl.data.personSetup

import io.paritytech.polkadotapp.common.data.worker.stateMachine.BaseWorkerStateMachine
import io.paritytech.polkadotapp.common.data.worker.stateMachine.WorkerStateMachine
import io.paritytech.polkadotapp.common.data.worker.stateMachine.WorkerStateMachineLocalSession
import io.paritytech.polkadotapp.feature_people_impl.data.personSetup.state.PersonSetupState
import io.paritytech.polkadotapp.feature_people_impl.data.personSetup.state.PersonSetupStateFactory
import javax.inject.Inject

typealias PersonSetupStateMachine = WorkerStateMachine<PersonSetupState>
typealias PersonSetupLocalSession = WorkerStateMachineLocalSession<PersonSetupState>

class PersonSetupStateMachineFactory @Inject constructor(
    private val stateFactory: PersonSetupStateFactory,
    private val localSession: PersonSetupLocalSession,
) {
    fun create(uploadSession: PersonSetupDataSource): PersonSetupStateMachine {
        return RealPersonSetupStateMachine(stateFactory, localSession, uploadSession)
    }
}

private class RealPersonSetupStateMachine(
    stateFactory: PersonSetupStateFactory,
    localSession: PersonSetupLocalSession,
    private val dataSource: PersonSetupDataSource,
) : BaseWorkerStateMachine<PersonSetupState, PersonSetupState.Transition>(
    localSession = localSession,
    stateFactory = stateFactory
) {
    override suspend fun createTransition(): PersonSetupState.Transition {
        return Transition()
    }

    private inner class Transition : PersonSetupState.Transition {
        override val dataSource: PersonSetupDataSource = this@RealPersonSetupStateMachine.dataSource
    }
}
