package io.paritytech.polkadotapp.feature_identity_impl.data.network.blockchain

import io.novasama.substrate_sdk_android.runtime.metadata.RuntimeMetadata
import io.novasama.substrate_sdk_android.runtime.metadata.module.Module
import io.paritytech.polkadotapp.chains.network.binding.bindString
import io.paritytech.polkadotapp.chains.storage.source.query.api.*
import io.paritytech.polkadotapp.chains.util.WithRuntime
import io.paritytech.polkadotapp.chains.util.identity
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityOf
import io.paritytech.polkadotapp.feature_identity_api.domain.models.PersonalIdentity
import io.paritytech.polkadotapp.feature_identity_impl.data.network.blockchain.models.UsernameInformation
import io.paritytech.polkadotapp.feature_identity_impl.data.network.blockchain.models.bindUsernameInformation
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonalAlias

@JvmInline
value class IdentityApi(override val module: Module) : QueryableModule

val RuntimeMetadata.identity: IdentityApi
    get() = IdentityApi(identity())

context(withRuntime: WithRuntime)
val IdentityApi.usernameInfoOf: QueryableStorageEntry1<ByteArray, UsernameInformation>
    get() = storage1("UsernameInfoOf", binding = { decoded, _ -> bindUsernameInformation(decoded) })

context(withRuntime: WithRuntime)
val IdentityApi.personIdentities: QueryableStorageEntry1<PersonalAlias, PersonalIdentity>
    get() = storage1(name = "PersonIdentities")

context(withRuntime: WithRuntime)
val IdentityApi.identityOf: QueryableStorageEntry1<AccountId, IdentityOf>
    get() = storage1(name = "IdentityOf")

context(withRuntime: WithRuntime)
val IdentityApi.usernameOf: QueryableStorageEntry1<ByteArray, String>
    get() = storage1("UsernameOf", binding = { decoded, _ -> bindString(decoded) })
