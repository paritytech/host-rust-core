package io.paritytech.polkadotapp.feature_videogame_impl.data

import io.novasama.substrate_sdk_android.runtime.metadata.RuntimeMetadata
import io.novasama.substrate_sdk_android.runtime.metadata.module.Module
import io.paritytech.polkadotapp.chains.storage.source.query.api.*
import io.paritytech.polkadotapp.chains.util.WithRuntime
import io.paritytech.polkadotapp.chains.util.score
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAccountOrPerson
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainParticipant
import io.paritytech.polkadotapp.feature_vouchers_api.data.model.PrivacyVoucherDenominationType

@JvmInline
value class ScoreApi(override val module: Module) : QueryableModule

val RuntimeMetadata.score: ScoreApi
    get() = ScoreApi(score())

context(withRuntime: WithRuntime)
val ScoreApi.participants: QueryableStorageEntry1<OnChainAccountOrPerson, OnChainParticipant>
    get() = storage1("Participants")

context(withRuntime: WithRuntime)
val ScoreApi.personhoodThreshold: QueryableStorageEntry0<Int>
    get() = storage0("PersonhoodThreshold")

context(withRuntime: WithRuntime)
val ScoreApi.voucherType: PrivacyVoucherDenominationType
    get() = constant("VoucherType")
