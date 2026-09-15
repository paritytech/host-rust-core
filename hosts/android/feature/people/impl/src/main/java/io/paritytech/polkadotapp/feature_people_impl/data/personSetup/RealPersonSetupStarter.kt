package io.paritytech.polkadotapp.feature_people_impl.data.personSetup

import io.paritytech.polkadotapp.common.presentation.resources.ContextManager
import io.paritytech.polkadotapp.feature_people_api.data.personSetup.PersonSetupStarter
import javax.inject.Inject

class RealPersonSetupStarter @Inject constructor(
    private val contextManager: ContextManager,
    private val personSetupLocalSession: PersonSetupLocalSession,
) : PersonSetupStarter {
    override fun startPersonSetup() {
        PersonSetupWorker.startPersonSetup(contextManager.applicationContext)
    }

    override suspend fun resetProgress() {
        personSetupLocalSession.resetState()
    }
}
