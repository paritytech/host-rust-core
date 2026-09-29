package io.paritytech.polkadotapp.feature_become_citizen_api.data.repository

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.DesignedTattooFlatId
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamily
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyIndex
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyMetadata
import kotlinx.coroutines.flow.Flow

interface TattooRepository {
    suspend fun getApplyDeposit(chain: Chain): Balance

    suspend fun getDesignFamilies(chainId: ChainId, indexes: List<TattooFamilyIndex>): Result<List<TattooFamily>>

    suspend fun getAllDesignFamilies(chainId: ChainId): Result<List<TattooFamily>>

    suspend fun getAllCommittedTattoos(chainId: ChainId): Result<Set<DesignedTattooFlatId>>

    suspend fun getDesignFamily(chainId: ChainId, familyIndex: TattooFamilyIndex): Result<TattooFamily?>

    suspend fun getTattooFamilyMetadata(familyId: ByteArray): Result<TattooFamilyMetadata>

    fun subscribePendingInvites(chainId: ChainId, inviter: AccountId, invitee: AccountId): Flow<Boolean>

    suspend fun flakeOut(chain: Chain): Result<Unit>
}
