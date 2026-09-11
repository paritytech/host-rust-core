package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate

import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.EvidenceUploadingNonTerminalState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceStateFactory
import io.paritytech.polkadotapp.feature_people_api.data.personSetup.PersonSetupStarter

// This step is needed even in the presence of Issuing Citizenship screen that launches Person Setup worker
// since we want to advance progress even when the app is not opened
class StartPersonSetupState(
    private val personSetupStarter: PersonSetupStarter,
    private val stateFactory: UploadEvidenceStateFactory,
) : EvidenceUploadingNonTerminalState() {
    companion object {
        const val ID = "StartPersonSetup"
    }

    override val id: String = ID

    context(transition: UploadEvidenceState.Transition)
    override suspend fun performNonTerminalTransition(): Result<UploadEvidenceState> {
        return runCatching {
            personSetupStarter.startPersonSetup()

            stateFactory.allDone()
        }
    }
}
