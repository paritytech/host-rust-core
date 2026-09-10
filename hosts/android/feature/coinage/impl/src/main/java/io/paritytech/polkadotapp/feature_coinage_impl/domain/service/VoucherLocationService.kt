package io.paritytech.polkadotapp.feature_coinage_impl.domain.service

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchPublicKey
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.common.data.cache.CacheableDataConsistency
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.utils.getOrEmpty
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.common.utils.mapToSet
import io.paritytech.polkadotapp.common.utils.mapValuesNotNull
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RecyclerVoucher
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.toRingCollectionId
import io.paritytech.polkadotapp.feature_coinage_impl.data.config.CoinageInstanceIdProvider
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.VoucherRepository
import io.paritytech.polkadotapp.feature_members_api.data.model.RingCollectionId
import io.paritytech.polkadotapp.feature_members_api.data.model.RingCollectionIdWithIndex
import io.paritytech.polkadotapp.feature_members_api.data.model.RingPosition
import io.paritytech.polkadotapp.feature_members_api.data.model.RingStatus
import io.paritytech.polkadotapp.feature_members_api.data.model.includedOrNull
import io.paritytech.polkadotapp.feature_members_api.data.model.includesKey
import io.paritytech.polkadotapp.feature_members_api.data.repository.MembersRepository
import io.paritytech.polkadotapp.feature_tokens_api.di.DigitalDollarChainAssetProvider
import io.paritytech.polkadotapp.feature_tokens_api.domain.ChainAssetProvider
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import javax.inject.Inject
import kotlin.collections.component1
import kotlin.collections.component2

private typealias VoucherKey = Pair<RingCollectionId, BandersnatchPublicKey>
private typealias VoucherPositions = Map<VoucherKey, RingPosition?>
private typealias RingStatuses = Map<RingCollectionIdWithIndex, RingStatus?>

class VoucherLocationService @Inject constructor(
    @param:DigitalDollarChainAssetProvider private val chainAssetProvider: ChainAssetProvider,
    private val voucherRepository: VoucherRepository,
    private val membersRepository: MembersRepository,
    private val coinageInstanceIdProvider: CoinageInstanceIdProvider,
) {
    context(scope: ComputationalScope)
    fun start() {
        val chainId = chainAssetProvider.chainId()

        subscribeVoucherPositions(chainId)
            .flatMapLatest { positions ->
                subscribeRingStatusesFor(chainId, positions)
                    .map { statuses -> positions to statuses }
            }
            .onEach { (positions, ringStatuses) ->
                voucherRepository.updateLocations(resolveLocations(positions, ringStatuses))
            }
            .launchIn(scope)
    }

    private fun subscribeVoucherPositions(chainId: ChainId): Flow<VoucherPositions> {
        // Every voucher, not just the ones outside a recycler: a ring keeps filling after a voucher lands
        // in it, and the member count is what the strategies read to decide when it may be spent.
        return voucherRepository.subscribeAllVouchers()
            .filter { it.isNotEmpty() }
            .distinctUntilChangedBy { vouchers -> vouchers.mapToSet { it.ringVrfPublicKey } }
            .flatMapLatest { vouchers ->
                val instanceId = coinageInstanceIdProvider.instanceId()
                    .getOrElse { return@flatMapLatest flowOf(Result.failure(it)) }
                val keys = vouchers.map { it.recyclerValue.toRingCollectionId(instanceId) to it.ringVrfPublicKey }

                membersRepository.subscribeMembers(
                    chainId = chainId,
                    keys = keys,
                    consistency = CacheableDataConsistency.CONSISTENT_WITH_REMOTE,
                )
            }
            .map { it.logFailure("Can't fetch location for vouchers").getOrEmpty() }
    }

    private fun subscribeRingStatusesFor(
        chainId: ChainId,
        positions: VoucherPositions,
    ): Flow<RingStatuses> {
        val ringKeys = positions.distinctRingStatusKeys()

        return membersRepository.subscribeRingStatuses(chainId, ringKeys)
            .map { it.logFailure("Can't fetch ring statuses for voucher locations").getOrEmpty() }
    }

    private fun VoucherPositions.distinctRingStatusKeys(): List<RingCollectionIdWithIndex> {
        return entries
            .mapNotNull { (voucherKey, ringPosition) ->
                val included = ringPosition?.includedOrNull() ?: return@mapNotNull null
                val ringCollectionId = voucherKey.first
                ringCollectionId to included.ringIndex
            }
            .distinct()
    }

    private fun resolveLocations(
        positions: VoucherPositions,
        ringStatuses: RingStatuses,
    ): Map<BandersnatchPublicKey, RecyclerVoucher.Location.InRecycler> {
        return positions.mapValuesNotNull { (voucherKey, voucherPosition) ->
            val position = voucherPosition?.includedOrNull() ?: return@mapValuesNotNull null
            val ringStatusKey = voucherKey.first to position.ringIndex
            val ringStatus = ringStatuses[ringStatusKey] ?: return@mapValuesNotNull null

            if (ringStatus.includesKey(position)) {
                // included, not total: a proof only verifies against the keys baked into the ring root, so
                // that is the set this voucher actually hides in.
                RecyclerVoucher.Location.InRecycler(position.ringIndex, ringStatus.included)
            } else {
                null
            }
        }
            .mapKeys { it.key.second }
    }
}
