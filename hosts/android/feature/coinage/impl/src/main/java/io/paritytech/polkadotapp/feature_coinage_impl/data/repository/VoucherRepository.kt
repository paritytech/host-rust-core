package io.paritytech.polkadotapp.feature_coinage_impl.data.repository

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchPublicKey
import io.paritytech.polkadotapp.chains.di.RemoteSourceQualifier
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.chains.storage.source.query.api.StorageKey4
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.chains.storage.source.queryCatching
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.common.utils.mapList
import io.paritytech.polkadotapp.database.dao.RecyclerVoucherDao
import io.paritytech.polkadotapp.database.dao.RecyclerVoucherLocationUpdate
import io.paritytech.polkadotapp.database.model.RecyclerVoucherLocal
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.CoinageInstanceId
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.DerivationIndex
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RecyclerIndex
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RecyclerVoucher
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.ValueExponent
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.filterInRecycler
import io.paritytech.polkadotapp.feature_coinage_impl.data.blockchain.coinage
import io.paritytech.polkadotapp.feature_coinage_impl.data.blockchain.recyclerAliasStates
import io.paritytech.polkadotapp.feature_coinage_impl.data.blockchain.recyclersCoinToRecycler
import io.paritytech.polkadotapp.feature_coinage_impl.data.model.OnChainAliasState
import io.paritytech.polkadotapp.feature_coinage_impl.domain.common.getNextIndex
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.math.BigInteger
import javax.inject.Inject

interface VoucherRepository {
    suspend fun save(voucher: RecyclerVoucher)

    fun subscribeAllVouchers(): Flow<List<RecyclerVoucher>>

    suspend fun updateLocations(locations: Map<BandersnatchPublicKey, RecyclerVoucher.Location.InRecycler>)

    suspend fun getNextDerivationIndex(): DerivationIndex

    suspend fun saveAll(vouchers: List<RecyclerVoucher>)

    /** Vouchers that are in a recycler. Says nothing about whether they may be used — see the ledger. */
    suspend fun getVouchersInRecycler(): List<RecyclerVoucher>

    suspend fun getAllVouchers(): List<RecyclerVoucher>

    suspend fun fetchValuesForKeys(
        chainId: ChainId,
        instanceId: CoinageInstanceId,
        voucherKeys: List<BandersnatchPublicKey>
    ): Result<Map<BandersnatchPublicKey, ValueExponent>>

    suspend fun getByRingVrfKeyIndices(indices: List<DerivationIndex>): List<RecyclerVoucher>

    fun subscribeVouchersInRecycler(): Flow<List<RecyclerVoucher>>

    suspend fun fetchRecyclerAliasStates(
        chainId: ChainId,
        keys: List<StorageKey4<BigInteger, BigInteger, BigInteger, ByteArray>>
    ): Result<Map<String, OnChainAliasState?>>
}

fun VoucherRepository.subscribeReadyToUseVouchers(): Flow<List<RecyclerVoucher>> {
    return subscribeVouchersInRecycler().map { vouchers -> vouchers.filterInRecycler() }
}

class RealVoucherRepository @Inject constructor(
    private val recyclerVoucherDao: RecyclerVoucherDao,
    @param:RemoteSourceQualifier private val remoteStorageSource: StorageDataSource
) : VoucherRepository {
    override suspend fun save(voucher: RecyclerVoucher) {
        recyclerVoucherDao.insert(voucher.toLocal())
    }

    override suspend fun saveAll(vouchers: List<RecyclerVoucher>) {
        recyclerVoucherDao.insertAll(vouchers.map { it.toLocal() })
    }

    override fun subscribeAllVouchers(): Flow<List<RecyclerVoucher>> {
        return recyclerVoucherDao.subscribeAll().mapList { it.toDomain() }
    }

    override suspend fun updateLocations(locations: Map<BandersnatchPublicKey, RecyclerVoucher.Location.InRecycler>) {
        val updates = locations.map { (publicKey, location) ->
            RecyclerVoucherLocationUpdate(
                ringVrfPublicKey = publicKey.value,
                recyclerIndex = location.recyclerIndex.value.toInt(),
                recyclerMembers = location.recyclerMembers
            )
        }
        recyclerVoucherDao.updateLocations(updates)
    }

    override suspend fun getByRingVrfKeyIndices(indices: List<DerivationIndex>): List<RecyclerVoucher> {
        return recyclerVoucherDao.getByRingVrfKeyIndices(indices).map { it.toDomain() }
    }

    override suspend fun getNextDerivationIndex(): DerivationIndex {
        return recyclerVoucherDao.getMaxRingVrfKeyIndex().getNextIndex()
    }

    override suspend fun fetchRecyclerAliasStates(
        chainId: ChainId,
        keys: List<StorageKey4<BigInteger, BigInteger, BigInteger, ByteArray>>
    ): Result<Map<String, OnChainAliasState?>> {
        return remoteStorageSource.queryCatching(chainId) {
            metadata.coinage.recyclerAliasStates.entries(keys)
        }
            .map {
                it.mapKeys { (key, _) -> key.fourth.toDataByteArray().toString() }
            }
    }

    override suspend fun getVouchersInRecycler(): List<RecyclerVoucher> {
        return recyclerVoucherDao.getVouchersInRecycler().map { it.toDomain() }
    }

    override suspend fun getAllVouchers(): List<RecyclerVoucher> {
        return recyclerVoucherDao.getAllVouchers().map { it.toDomain() }
    }

    override fun subscribeVouchersInRecycler(): Flow<List<RecyclerVoucher>> {
        return recyclerVoucherDao.subscribeVouchersInRecycler().mapList { it.toDomain() }
    }

    override suspend fun fetchValuesForKeys(
        chainId: ChainId,
        instanceId: CoinageInstanceId,
        voucherKeys: List<BandersnatchPublicKey>
    ): Result<Map<BandersnatchPublicKey, ValueExponent>> {
        return remoteStorageSource.queryCatching(chainId) {
            metadata.coinage.recyclersCoinToRecycler.entries(voucherKeys)
        }
            .map { entries ->
                entries
                    .filterValues { location -> location.instanceId.toUInt() == instanceId }
                    .mapValues { (_, location) -> ValueExponent(location.value) }
            }
    }

    private fun RecyclerVoucherLocal.toDomain(): RecyclerVoucher {
        return RecyclerVoucher(
            ringVrfKeyIndex = ringVrfKeyIndex,
            ringVrfPublicKey = ringVrfPublicKey.toDataByteArray(),
            recyclerValue = ValueExponent(recyclerValue),
            location = toDomainLocation(),
        )
    }

    private fun RecyclerVoucherLocal.toDomainLocation(): RecyclerVoucher.Location {
        val index = locationRecyclerIndex ?: return RecyclerVoucher.Location.Unknown

        // Written together by the location service, so one without the other is a corrupt row rather than a
        // state worth guessing at.
        val members = requireNotNull(recyclerMembers) { "Voucher in recycler $index has no member count" }

        return RecyclerVoucher.Location.InRecycler(
            recyclerIndex = RecyclerIndex(index.toBigInteger()),
            recyclerMembers = members
        )
    }

    private fun RecyclerVoucher.toLocal(): RecyclerVoucherLocal {
        val inRecycler = location as? RecyclerVoucher.Location.InRecycler
        return RecyclerVoucherLocal(
            ringVrfKeyIndex = ringVrfKeyIndex,
            ringVrfPublicKey = ringVrfPublicKey.value,
            recyclerValue = recyclerValue.value,
            locationRecyclerIndex = inRecycler?.recyclerIndex?.value?.toInt(),
            recyclerMembers = inRecycler?.recyclerMembers,
        )
    }
}
