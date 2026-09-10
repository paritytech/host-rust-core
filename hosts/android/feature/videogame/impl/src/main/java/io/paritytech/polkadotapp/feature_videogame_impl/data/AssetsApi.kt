package io.paritytech.polkadotapp.feature_videogame_impl.data

import io.novasama.substrate_sdk_android.runtime.metadata.RuntimeMetadata
import io.novasama.substrate_sdk_android.runtime.metadata.module
import io.novasama.substrate_sdk_android.runtime.metadata.module.Module
import io.paritytech.polkadotapp.chains.storage.source.query.api.*
import io.paritytech.polkadotapp.chains.util.WithRuntime
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAssetMetadata
import io.paritytech.polkadotapp.feature_xcm_api.multiLocation.RelativeMultiLocation

// Minimal Assets pallet binding — only Metadata.decimals is read, to scale the prize amount
// to whole units. The runtime's Assets instance is keyed by an XCM Location (not a scalar id),
// matching the prize's assetId.
@JvmInline
value class AssetsApi(override val module: Module) : QueryableModule

val RuntimeMetadata.assets: AssetsApi
    get() = AssetsApi(module("Assets"))

context(withRuntime: WithRuntime)
val AssetsApi.assetMetadata: QueryableStorageEntry1<RelativeMultiLocation, OnChainAssetMetadata>
    get() = storage1("Metadata")
