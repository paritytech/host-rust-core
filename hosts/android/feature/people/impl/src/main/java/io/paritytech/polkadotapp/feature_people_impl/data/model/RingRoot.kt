package io.paritytech.polkadotapp.feature_people_impl.data.model

import io.paritytech.polkadotapp.feature_members_api.data.model.RingRoot

fun RingRoot.isAliasUpToDate(alias: RevisedContextualAlias): Boolean {
    return alias.revision == revision
}
