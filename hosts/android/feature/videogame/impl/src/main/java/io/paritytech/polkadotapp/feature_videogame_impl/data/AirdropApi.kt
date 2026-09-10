package io.paritytech.polkadotapp.feature_videogame_impl.data

import io.novasama.substrate_sdk_android.runtime.metadata.RuntimeMetadata
import io.novasama.substrate_sdk_android.runtime.metadata.module
import io.novasama.substrate_sdk_android.runtime.metadata.module.Module
import io.novasama.substrate_sdk_android.runtime.metadata.moduleOrNull
import io.paritytech.polkadotapp.chains.storage.source.query.api.*
import io.paritytech.polkadotapp.chains.util.WithRuntime
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainActiveEvent
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAirdropRegistrationEntry

/**
 * pallet-airdrop storage. Resolves `Airdrop` first, then `NewAirdrop`, so the binding
 * survives the pallet rename; on runtimes with neither module the storage reads throw
 * and the caller falls back.
 */
@JvmInline
value class AirdropApi(override val module: Module) : QueryableModule

val RuntimeMetadata.airdrop: AirdropApi
    get() = AirdropApi(moduleOrNull(AIRDROP_MODULE) ?: module(NEW_AIRDROP_MODULE))

context(withRuntime: WithRuntime)
val AirdropApi.events: QueryableStorageEntry1<AirdropEventKey, OnChainActiveEvent>
    get() = storage1("Events")

context(withRuntime: WithRuntime)
val AirdropApi.registrations: QueryableStorageEntry2<AirdropEventKey, TicketSlot, OnChainAirdropRegistrationEntry>
    get() = storage2("Registrations")

context(withRuntime: WithRuntime)
val AirdropApi.winners: QueryableStorageEntry2<AirdropEventKey, OnChainAirdropRegistrationEntry, TicketSlot>
    get() = storage2("Winners")

private const val AIRDROP_MODULE = "Airdrop"
private const val NEW_AIRDROP_MODULE = "NewAirdrop"
