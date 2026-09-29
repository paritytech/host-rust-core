package io.paritytech.polkadotapp.feature_videogame_impl.data.collectibles

import io.novasama.substrate_sdk_android.extensions.toHexString
import io.paritytech.polkadotapp.chains.di.RemoteSourceQualifier
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.chains.storage.source.queryCatching
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.domain.model.Timestamp
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAccountOrPerson
import io.paritytech.polkadotapp.feature_videogame_impl.data.nftCandidates
import io.paritytech.polkadotapp.feature_videogame_impl.data.nfts
import io.paritytech.polkadotapp.feature_videogame_impl.data.videoGame
import io.paritytech.polkadotapp.feature_videogame_impl.domain.collectibles.OwnedNft
import javax.inject.Inject

interface CollectiblesRepository {
    context(scope: ComputationalScope)
    suspend fun getOwnedNfts(
        chainId: ChainId,
        owners: List<OnChainAccountOrPerson>
    ): Result<List<OwnedNft>>
}

class RealCollectiblesRepository @Inject constructor(
    @RemoteSourceQualifier private val remoteStorageSource: StorageDataSource,
) : CollectiblesRepository {
    context(scope: ComputationalScope)
    override suspend fun getOwnedNfts(
        chainId: ChainId,
        owners: List<OnChainAccountOrPerson>
    ): Result<List<OwnedNft>> {
        return remoteStorageSource.queryCatching(chainId) {
            val confirmed = mutableMapOf<String, Timestamp>()
            val pending = mutableSetOf<String>()

            owners.forEach { owner ->
                metadata.videoGame.nfts.entries(owner).forEach { (key, mintedAt) ->
                    confirmed[key.second.value.toHexString()] = mintedAt.toLong()
                }
                metadata.videoGame.nftCandidates.keys(owner).forEach { (_, hash) ->
                    pending.add(hash.toHexString())
                }
            }

            val confirmedNfts = confirmed.map { (hash, mintedAt) ->
                OwnedNft(hash = hash, mintedAt = mintedAt, pending = null)
            }
            val pendingNfts = pending
                .filterNot { it in confirmed.keys }
                .map { OwnedNft(hash = it, mintedAt = null, pending = true) }

            confirmedNfts + pendingNfts
        }
    }
}
