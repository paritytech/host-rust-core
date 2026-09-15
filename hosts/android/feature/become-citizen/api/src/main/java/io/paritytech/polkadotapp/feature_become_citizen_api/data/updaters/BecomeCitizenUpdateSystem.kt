package io.paritytech.polkadotapp.feature_become_citizen_api.data.updaters

import io.paritytech.polkadotapp.chains.network.updaters.system.UpdateSystem

class BecomeCitizenUpdateSystem(
    val peopleUpdateSystem: UpdateSystem,
    val bulletInUpdateSystem: UpdateSystem
)
