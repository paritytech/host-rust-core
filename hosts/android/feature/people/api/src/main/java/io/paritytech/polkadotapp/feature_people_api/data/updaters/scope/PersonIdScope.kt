package io.paritytech.polkadotapp.feature_people_api.data.updaters.scope

import io.paritytech.polkadotapp.chains.network.updaters.Updater
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId

interface PersonIdScope : Updater.Scope<PersonId?>
