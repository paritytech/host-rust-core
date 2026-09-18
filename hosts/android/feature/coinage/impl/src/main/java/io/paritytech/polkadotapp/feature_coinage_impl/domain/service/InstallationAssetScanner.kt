package io.paritytech.polkadotapp.feature_coinage_impl.domain.service

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchPublicKey
import io.paritytech.polkadotapp.bandersnatch_crypto.aliasInContext
import io.paritytech.polkadotapp.chains.storage.source.query.api.StorageKey4
import io.paritytech.polkadotapp.common.data.cache.CacheableDataConsistency
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.common.utils.filterNotNull
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.measureExecution
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.Coin
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.Coin.Age
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.CoinProvenance
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.CoinageInstallationId
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.CoinageKeyIndex
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RecyclerFungibility
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RecyclerVoucher
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RecyclerVoucher.Location
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.ValueExponent
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.toRingCollectionId
import io.paritytech.polkadotapp.feature_coinage_impl.data.config.CoinageInstanceIdProvider
import io.paritytech.polkadotapp.feature_coinage_impl.data.derivation.CoinKeypairDerivation
import io.paritytech.polkadotapp.feature_coinage_impl.data.derivation.VoucherRingDerivation
import io.paritytech.polkadotapp.feature_coinage_impl.data.derivation.getDerivedAccountIds
import io.paritytech.polkadotapp.feature_coinage_impl.data.derivation.getDerivedMemberKeys
import io.paritytech.polkadotapp.feature_coinage_impl.data.model.OnChainAliasState
import io.paritytech.polkadotapp.feature_coinage_impl.data.model.OnChainCoinInfo
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.CoinRepository
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.VoucherRepository
import io.paritytech.polkadotapp.feature_coinage_impl.data.signer.context.CoinageSigningContextProvider
import io.paritytech.polkadotapp.feature_members_api.data.model.RingPosition
import io.paritytech.polkadotapp.feature_members_api.data.repository.MembersRepository
import io.paritytech.polkadotapp.feature_tokens_api.di.DigitalDollarChainAssetProvider
import io.paritytech.polkadotapp.feature_tokens_api.domain.ChainAssetProvider
import javax.inject.Inject

interface InstallationAssetScanner {
    suspend fun scanCoins(installation: CoinageInstallationId, startIndex: Int, count: Int): Result<List<Coin>>

    suspend fun scanVouchers(installation: CoinageInstallationId, startIndex: Int, count: Int): Result<List<RecyclerVoucher>>
}

class RealInstallationAssetScanner @Inject constructor(
    @param:DigitalDollarChainAssetProvider private val chainAssetProvider: ChainAssetProvider,
    private val coinsRepository: CoinRepository,
    private val voucherRepository: VoucherRepository,
    private val membersRepository: MembersRepository,
    private val keypairDerivation: CoinKeypairDerivation,
    private val voucherRingDerivation: VoucherRingDerivation,
    private val coinageSigningContextProvider: CoinageSigningContextProvider,
    private val coinageInstanceIdProvider: CoinageInstanceIdProvider,
) : InstallationAssetScanner {
    private val chainId = chainAssetProvider.chainId()

    override suspend fun scanCoins(installation: CoinageInstallationId, startIndex: Int, count: Int): Result<List<Coin>> {
        val indices = indicesOf(installation, startIndex, count)
        val accounts = measureExecution("deriving accounts for coins") {
            keypairDerivation.getDerivedAccountIds(indices).zip(indices).toMap()
        }

        return measureExecution("fetching on chain data for coins batch") {
            coinsRepository.fetchCoinsInfoFor(chainId, accounts.keys.toList())
        }
            .map { it.filterNotNull() }
            .map { it.toCoins(accounts) }
    }

    override suspend fun scanVouchers(
        installation: CoinageInstallationId,
        startIndex: Int,
        count: Int
    ): Result<List<RecyclerVoucher>> {
        val indices = indicesOf(installation, startIndex, count)
        val keys = measureExecution("Deriving accounts for vouchers") {
            voucherRingDerivation.getDerivedMemberKeys(indices).zip(indices).toMap()
        }

        return fetchVouchersOnChainData(keys.keys.toList())
            .flatMap { (values, records) ->
                val detected = records.toVouchers(keys, values)

                fetchNotUnloadedVouchers(detected.filter { it.location is Location.InRecycler })
                    .map { inRecycler -> inRecycler + detected.filter { it.location is Location.Onboarding } }
            }
    }

    private fun indicesOf(installation: CoinageInstallationId, startIndex: Int, count: Int) =
        (startIndex until startIndex + count).map { CoinageKeyIndex(installation, it) }

    private fun Map<AccountId, OnChainCoinInfo>.toCoins(accounts: Map<AccountId, CoinageKeyIndex>) = mapNotNull { (accountId, onChainInfo) ->
        Coin(
            derivationIndex = accounts[accountId] ?: return@mapNotNull null,
            valueExponent = ValueExponent(onChainInfo.value),
            accountId = accountId,
            // Recovered from a read that found it, so it is on chain by construction.
            age = Age.Known(onChainInfo.age),
            isOnChain = true,
            // Recovery reads value and age, never where the coin has been. Left unobserved so the presence
            // sync fills the history in from the age, the same way it does for a claimed coin.
            provenance = CoinProvenance.UNKNOWN
        )
    }

    private fun Map<BandersnatchPublicKey, RingPosition>.toVouchers(
        keys: Map<BandersnatchPublicKey, CoinageKeyIndex>,
        values: Map<BandersnatchPublicKey, ValueExponent>
    ) = mapNotNull { (publicKey, onChainInfo) ->
        RecyclerVoucher(
            ringVrfKeyIndex = keys[publicKey] ?: return@mapNotNull null,
            ringVrfPublicKey = publicKey,
            recyclerValue = values[publicKey] ?: return@mapNotNull null,
            location = onChainInfo.getVoucherLocation(),
            // Recovery knows where the voucher sits, not how drained its ring is. Zero until the location
            // service reads it; the max is left unfrozen so that service writes a real one rather than
            // inheriting this placeholder.
            recyclerFungibility = RecyclerFungibility.NONE,
            maxRecyclerFungibility = null,
        )
    }

    private suspend fun fetchNotUnloadedVouchers(detected: List<RecyclerVoucher>): Result<List<RecyclerVoucher>> {
        if (detected.isEmpty()) return Result.success(listOf())
        return coinageInstanceIdProvider.instanceId().flatMap { instanceId ->
            val keys = detected.mapNotNull {
                val location = (it.location as? Location.InRecycler) ?: return@mapNotNull null
                val aliasContext = coinageSigningContextProvider.recyclerVouchersContext()
                val alias = voucherRingDerivation.deriveBandersnatch(it.ringVrfKeyIndex).aliasInContext(aliasContext)

                it to StorageKey4(
                    instanceId.toLong().toBigInteger(),
                    it.recyclerValue.value.toBigInteger(),
                    location.recyclerIndex.value,
                    alias.value
                )
            }.toMap()

            voucherRepository.fetchRecyclerAliasStates(chainId, keys.values.toList())
                .map { aliasStates ->
                    keys
                        .mapValues { (_, value) -> value.fourth.toDataByteArray().toString() }
                        .mapNotNull { if (aliasStates[it.value] is OnChainAliasState.Unloaded) null else it.key }
                }
        }
    }

    private suspend fun fetchVouchersOnChainData(keys: List<BandersnatchPublicKey>) = measureExecution("Fetching vouchers on chain info") {
        coinageInstanceIdProvider.instanceId().flatMap { instanceId ->
            voucherRepository.fetchValuesForKeys(chainId, instanceId, keys)
                .map { it.filterNotNull() }
                .flatMap { values ->
                    val pairs = values.map { (key, exponent) -> exponent.toRingCollectionId(instanceId) to key }

                    membersRepository.fetchMembers(
                        chainId = chainId,
                        keys = pairs,
                        consistency = CacheableDataConsistency.CONSISTENT_WITH_REMOTE,
                    ).map { recordsByPair ->
                        val recordsByKey = recordsByPair.filterNotNull()
                            .mapKeys { (pair, _) -> pair.second }

                        values to recordsByKey
                    }
                }
        }
    }

    private fun RingPosition.getVoucherLocation() = when (this) {
        // Recovery knows where the voucher sits, not how full the ring is. Zero until the location service
        // reads it, so nothing releases the voucher on an anonymity set we have not seen.
        is RingPosition.Included -> Location.InRecycler(ringIndex, recyclerMembers = 0, enteredAt = null)
        is RingPosition.Onboarding -> Location.Onboarding
        is RingPosition.Suspended -> Location.Unknown
    }
}
