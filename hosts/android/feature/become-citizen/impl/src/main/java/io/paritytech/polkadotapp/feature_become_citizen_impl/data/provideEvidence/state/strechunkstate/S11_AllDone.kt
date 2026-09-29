package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate

import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.EvidenceUploadingTerminalState

class AllDone : EvidenceUploadingTerminalState() {
    companion object {
        val ID = "AllDone"
    }

    override val id = ID
}
