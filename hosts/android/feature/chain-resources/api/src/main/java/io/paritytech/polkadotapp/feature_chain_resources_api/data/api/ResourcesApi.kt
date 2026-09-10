package io.paritytech.polkadotapp.feature_chain_resources_api.data.api

import io.novasama.substrate_sdk_android.runtime.metadata.RuntimeMetadata
import io.novasama.substrate_sdk_android.runtime.metadata.module.Module
import io.paritytech.polkadotapp.chains.storage.source.query.api.QueryableModule
import io.paritytech.polkadotapp.chains.storage.source.query.api.QueryableStorageEntry0
import io.paritytech.polkadotapp.chains.storage.source.query.api.QueryableStorageEntry1
import io.paritytech.polkadotapp.chains.storage.source.query.api.storage0
import io.paritytech.polkadotapp.chains.storage.source.query.api.storage1
import io.paritytech.polkadotapp.chains.util.WithRuntime
import io.paritytech.polkadotapp.chains.util.resources
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_chain_resources_api.data.model.OnChainConsumerInfo
import io.paritytech.polkadotapp.feature_chain_resources_api.data.model.OnChainReservationQueueEntry
import java.math.BigInteger

@JvmInline
value class ResourcesApi(override val module: Module) : QueryableModule

val RuntimeMetadata.resources: ResourcesApi
    get() = ResourcesApi(resources())

context(withRuntime: WithRuntime)
val ResourcesApi.consumers: QueryableStorageEntry1<AccountId, OnChainConsumerInfo>
    get() = storage1("Consumers")

context(withRuntime: WithRuntime)
val ResourcesApi.usernameOwnerOf: QueryableStorageEntry1<String, AccountId>
    get() = storage1("UsernameOwnerOf")

context(withRuntime: WithRuntime)
val ResourcesApi.usernameReservationQueue: QueryableStorageEntry1<String, List<OnChainReservationQueueEntry>>
    get() = storage1("UsernameReservationQueue")

context(withRuntime: WithRuntime)
val ResourcesApi.reservationDuration: QueryableStorageEntry0<BigInteger>
    get() = storage0("UsernameReservationDuration")
