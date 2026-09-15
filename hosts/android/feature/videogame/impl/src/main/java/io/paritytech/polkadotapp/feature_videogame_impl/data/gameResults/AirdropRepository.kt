package io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults

import io.paritytech.polkadotapp.chains.di.RemoteSourceQualifier
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.chains.storage.source.queryCatching
import io.paritytech.polkadotapp.feature_videogame_impl.data.TicketSlot
import io.paritytech.polkadotapp.feature_videogame_impl.data.airdrop
import io.paritytech.polkadotapp.feature_videogame_impl.data.assetMetadata
import io.paritytech.polkadotapp.feature_videogame_impl.data.assets
import io.paritytech.polkadotapp.feature_videogame_impl.data.events
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainActiveEvent
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAirdropRegistrationEntry
import io.paritytech.polkadotapp.feature_videogame_impl.data.registrations
import io.paritytech.polkadotapp.feature_videogame_impl.data.winners
import io.paritytech.polkadotapp.feature_xcm_api.multiLocation.RelativeMultiLocation
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

interface AirdropRepository {
    suspend fun getActiveEvent(chainId: ChainId, eventId: AirdropEventId): Result<OnChainActiveEvent?>

    /** Live subscription to the airdrop event for [eventId] — pushes on every new block. */
    fun subscribeActiveEvent(chainId: ChainId, eventId: AirdropEventId): Flow<OnChainActiveEvent?>

    /** Registrations for [eventId], keyed by ticket slot. */
    suspend fun getRegistrations(
        chainId: ChainId,
        eventId: AirdropEventId
    ): Result<Map<TicketSlot, OnChainAirdropRegistrationEntry>>

    /** Winners for [eventId]: registration entry → winning ticket slot. */
    suspend fun getWinners(
        chainId: ChainId,
        eventId: AirdropEventId
    ): Result<Map<OnChainAirdropRegistrationEntry, TicketSlot>>

    suspend fun getAssetDecimals(chainId: ChainId, assetId: RelativeMultiLocation): Result<Int?>
}

class RealAirdropRepository @Inject constructor(
    @param:RemoteSourceQualifier private val storageDataSource: StorageDataSource,
) : AirdropRepository {
    override suspend fun getActiveEvent(chainId: ChainId, eventId: AirdropEventId): Result<OnChainActiveEvent?> {
        return storageDataSource.queryCatching(chainId, at = null) {
            metadata.airdrop.events.query(eventId.value)
        }
    }

    override fun subscribeActiveEvent(chainId: ChainId, eventId: AirdropEventId): Flow<OnChainActiveEvent?> {
        return storageDataSource.subscribe(chainId) {
            metadata.airdrop.events.observe(eventId.value)
        }
    }

    override suspend fun getRegistrations(
        chainId: ChainId,
        eventId: AirdropEventId
    ): Result<Map<TicketSlot, OnChainAirdropRegistrationEntry>> {
        return storageDataSource.queryCatching(chainId, at = null) {
            val keys = metadata.airdrop.registrations.keys(eventId.value)
            metadata.airdrop.registrations.entries(keys).mapKeys { (key, _) -> key.second }
        }
    }

    override suspend fun getWinners(
        chainId: ChainId,
        eventId: AirdropEventId
    ): Result<Map<OnChainAirdropRegistrationEntry, TicketSlot>> {
        return storageDataSource.queryCatching(chainId, at = null) {
            val keys = metadata.airdrop.winners.keys(eventId.value)
            metadata.airdrop.winners.entries(keys).mapKeys { (key, _) -> key.second }
        }
    }

    override suspend fun getAssetDecimals(chainId: ChainId, assetId: RelativeMultiLocation): Result<Int?> {
        return storageDataSource.queryCatching(chainId, at = null) {
            metadata.assets.assetMetadata.query(assetId)?.decimals?.toInt()
        }
    }
}
