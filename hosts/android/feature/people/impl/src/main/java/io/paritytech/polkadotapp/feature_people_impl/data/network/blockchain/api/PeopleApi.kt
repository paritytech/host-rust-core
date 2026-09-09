package io.paritytech.polkadotapp.feature_people_impl.data.network.blockchain.api

import io.novasama.substrate_sdk_android.runtime.metadata.RuntimeMetadata
import io.novasama.substrate_sdk_android.runtime.metadata.module
import io.novasama.substrate_sdk_android.runtime.metadata.module.Module
import io.paritytech.polkadotapp.chains.storage.source.query.api.QueryableModule
import io.paritytech.polkadotapp.chains.storage.source.query.api.QueryableStorageEntry0
import io.paritytech.polkadotapp.chains.storage.source.query.api.QueryableStorageEntry1
import io.paritytech.polkadotapp.chains.storage.source.query.api.storage0
import io.paritytech.polkadotapp.chains.storage.source.query.api.storage1
import io.paritytech.polkadotapp.chains.util.Modules
import io.paritytech.polkadotapp.chains.util.WithRuntime
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_account_api.domain.model.PersonPublicKey
import io.paritytech.polkadotapp.feature_people_api.data.model.PersonRecord
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import io.paritytech.polkadotapp.feature_people_impl.data.model.RevisedContextualAlias

@JvmInline
value class PeopleApi(override val module: Module) : QueryableModule

val RuntimeMetadata.people: PeopleApi
    get() = PeopleApi(module(Modules.PEOPLE))

context(withRuntime: WithRuntime)
val PeopleApi.keys: QueryableStorageEntry1<PersonPublicKey, PersonId>
    get() = storage1(name = "Keys")

context(withRuntime: WithRuntime)
val PeopleApi.accountToAlias: QueryableStorageEntry1<AccountId, RevisedContextualAlias>
    get() = storage1("AccountToAlias")

context(withRuntime: WithRuntime)
val PeopleApi.people: QueryableStorageEntry1<PersonId, PersonRecord>
    get() = storage1("People")

context(withRuntime: WithRuntime)
val PeopleApi.nextPersonId: QueryableStorageEntry0<PersonId>
    get() = storage0(name = "NextPersonalId")
