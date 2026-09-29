package io.paritytech.polkadotapp.feature_upgrade_username_impl.data

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.feature_account_api.domain.derivation.DerivationIndex32
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsTld
import io.paritytech.polkadotapp.feature_people_api.domain.personhoodProductContext

private const val RESOURCES_INDEX = 1u

internal fun BandersnatchContext.Companion.resources(tld: DotNsTld): BandersnatchContext {
    return personhoodProductContext(tld, DerivationIndex32.fromUInt(RESOURCES_INDEX))
}
