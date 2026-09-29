package io.paritytech.polkadotapp.feature_vouchers_impl.data

import io.novasama.substrate_sdk_android.runtime.metadata.RuntimeMetadata
import io.novasama.substrate_sdk_android.runtime.metadata.module.Module
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchAlias
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchPublicKey
import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.chains.storage.source.query.api.QueryableModule
import io.paritytech.polkadotapp.chains.storage.source.query.api.QueryableStorageEntry1
import io.paritytech.polkadotapp.chains.storage.source.query.api.QueryableStorageEntry2
import io.paritytech.polkadotapp.chains.storage.source.query.api.QueryableStorageEntry3
import io.paritytech.polkadotapp.chains.storage.source.query.api.storage1
import io.paritytech.polkadotapp.chains.storage.source.query.api.storage2
import io.paritytech.polkadotapp.chains.storage.source.query.api.storage3
import io.paritytech.polkadotapp.chains.util.WithRuntime
import io.paritytech.polkadotapp.chains.util.privacyVoucher
import io.paritytech.polkadotapp.feature_vouchers_api.data.model.PrivacyVoucherRingPosition
import java.math.BigInteger

@JvmInline
value class PrivacyVoucherApi(override val module: Module) : QueryableModule

val RuntimeMetadata.privacyVoucher: PrivacyVoucherApi
    get() = PrivacyVoucherApi(privacyVoucher())

context(withRuntime: WithRuntime)
val PrivacyVoucherApi.keys: QueryableStorageEntry2<Balance, BigInteger, List<BandersnatchPublicKey>>
    get() = storage2(name = "Keys")

context(withRuntime: WithRuntime)
val PrivacyVoucherApi.keysToRing: QueryableStorageEntry1<BandersnatchPublicKey, PrivacyVoucherRingPosition>
    get() = storage1(name = "KeysToRing")

context(withRuntime: WithRuntime)
val PrivacyVoucherApi.buildingRings: QueryableStorageEntry1<BigInteger, Unit>
    get() = storage1("BuildingRings", binding = { _, _ -> })

context(withRuntime: WithRuntime)
val PrivacyVoucherApi.rings: QueryableStorageEntry2<Balance, BigInteger, Unit>
    get() = storage2("Rings")

val PrivacyVoucherApi.usedVouchers: QueryableStorageEntry3<Balance, BigInteger, BandersnatchAlias, Unit>
    get() = storage3(name = "UsedTickets")
