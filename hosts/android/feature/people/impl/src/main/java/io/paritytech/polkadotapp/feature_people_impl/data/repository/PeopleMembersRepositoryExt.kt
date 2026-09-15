package io.paritytech.polkadotapp.feature_people_impl.data.repository

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.network.binding.BlockHash
import io.paritytech.polkadotapp.common.data.cache.CacheableDataConsistency
import io.paritytech.polkadotapp.feature_account_api.domain.model.PersonPublicKey
import io.paritytech.polkadotapp.feature_members_api.data.model.RingCollectionId
import io.paritytech.polkadotapp.feature_members_api.data.model.RingIndex
import io.paritytech.polkadotapp.feature_members_api.data.model.RingPosition
import io.paritytech.polkadotapp.feature_members_api.data.model.RingRoot
import io.paritytech.polkadotapp.feature_members_api.data.model.RingStatus
import io.paritytech.polkadotapp.feature_members_api.data.repository.MembersRepository
import io.paritytech.polkadotapp.feature_members_api.data.repository.getMember
import io.paritytech.polkadotapp.feature_members_api.data.repository.getRingRoot
import io.paritytech.polkadotapp.feature_members_api.data.repository.getRingStatus
import io.paritytech.polkadotapp.feature_members_api.data.repository.subscribeMember
import io.paritytech.polkadotapp.feature_people_api.domain.PEOPLE
import kotlinx.coroutines.flow.Flow

fun MembersRepository.subscribePersonMember(
    chainId: ChainId,
    key: PersonPublicKey,
    consistency: CacheableDataConsistency,
): Flow<Result<RingPosition?>> {
    return subscribeMember(
        chainId = chainId,
        collectionId = RingCollectionId.PEOPLE,
        key = key,
        consistency = consistency,
    )
}

suspend fun MembersRepository.getPersonMember(
    chainId: ChainId,
    key: PersonPublicKey,
    consistency: CacheableDataConsistency,
): Result<RingPosition?> {
    return getMember(
        chainId = chainId,
        collectionId = RingCollectionId.PEOPLE,
        key = key,
        consistency = consistency,
    )
}

suspend fun MembersRepository.getPeopleRingRoot(
    chainId: ChainId,
    ringIndex: RingIndex,
    consistency: CacheableDataConsistency,
    blockHash: BlockHash? = null,
): Result<RingRoot?> {
    return getRingRoot(
        chainId = chainId,
        collectionId = RingCollectionId.PEOPLE,
        ringIndex = ringIndex,
        consistency = consistency,
        blockHash = blockHash,
    )
}

suspend fun MembersRepository.getPeopleRingStatus(
    chainId: ChainId,
    ringIndex: RingIndex,
    consistency: CacheableDataConsistency,
): Result<RingStatus?> {
    return getRingStatus(
        chainId = chainId,
        collectionId = RingCollectionId.PEOPLE,
        ringIndex = ringIndex,
        consistency = consistency,
    )
}
