package io.paritytech.polkadotapp.feature_people_api.data.personSetup

interface PersonSetupStarter {
    fun startPersonSetup()

    suspend fun resetProgress()
}
