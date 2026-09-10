package io.paritytech.polkadotapp.feature_people_impl.data.personSetup.state

import io.paritytech.polkadotapp.common.data.worker.stateMachine.NonTerminalState
import io.paritytech.polkadotapp.common.data.worker.stateMachine.TerminalState

abstract class PersonSetupTerminalState :
    PersonSetupState,
    TerminalState<PersonSetupState, PersonSetupState.Transition>()

abstract class PersonSetupNonTerminalState :
    PersonSetupState,
    NonTerminalState<PersonSetupState, PersonSetupState.Transition>()
