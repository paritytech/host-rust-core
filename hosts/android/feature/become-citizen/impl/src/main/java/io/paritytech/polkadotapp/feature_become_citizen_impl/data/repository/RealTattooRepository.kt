package io.paritytech.polkadotapp.feature_become_citizen_impl.data.repository

import io.paritytech.polkadotapp.chains.call.MultiChainRuntimeCallsApi
import io.paritytech.polkadotapp.chains.call.RuntimeCallsApi
import io.paritytech.polkadotapp.chains.di.RemoteSourceQualifier
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.chains.network.binding.bindBalance
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.chains.storage.source.queryCatching
import io.paritytech.polkadotapp.chains.util.utilityAsset
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.utils.coerceToUnit
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_balances_api.data.type.TokenBalanceTypeRegistry
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.api.committedDesigns
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.api.designFamilies
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.api.pendingInvites
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.api.proofOfInk
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.calls.apply
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.calls.flakeout
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.calls.proofOfInk
import io.paritytech.polkadotapp.feature_become_citizen_api.data.repository.TattooRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.DesignedTattooFlatId
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamily
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyIndex
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyMetadata
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.metadataFetcher.TattooFamilyMetadataFetcher
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.signer.proofOfInk.ProofOfInkOriginsFactory
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicService
import io.paritytech.polkadotapp.feature_transactions.api.data.flattenExecutionFailure
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

class RealTattooRepository @Inject constructor(
    @RemoteSourceQualifier private val remoteStorageDataSource: StorageDataSource,
    private val multiChainRuntimeCallsApi: MultiChainRuntimeCallsApi,
    private val tokenTypeRegistry: TokenBalanceTypeRegistry,
    private val tattooFamilyMetadataFetcher: TattooFamilyMetadataFetcher,
    private val extrinsicService: ExtrinsicService,
    private val proofOfInkOrigins: ProofOfInkOriginsFactory
) : TattooRepository {
    override suspend fun getApplyDeposit(chain: Chain): Balance {
        val runtimeApi = multiChainRuntimeCallsApi.forChain(chain.id)

        val candidacyDeposit = runtimeApi.candidacyDeposit()

        val applyFee = extrinsicService.estimateFee(
            chain = chain,
            origin = proofOfInkOrigins.foreground.applyWithDepositOrigin()
        ) {
            proofOfInk.apply()
        }
            .map { it.amount }
            .logFailure("Failed to calculate fee for apply deposit")
            .getOrDefault(Balance.ZERO)

        val chainAsset = chain.utilityAsset
        val minimumBalance = tokenTypeRegistry.typeFor(chainAsset).minimumBalance()

        // since commit is not feeless anymore, we multiply fee by 6 to have some extra buffer
        return candidacyDeposit + minimumBalance + applyFee * 6
    }

    override suspend fun getDesignFamilies(chainId: ChainId, indexes: List<TattooFamilyIndex>): Result<List<TattooFamily>> {
        return remoteStorageDataSource.queryCatching(chainId) {
            metadata.proofOfInk.designFamilies.entries(indexes)
                .values
                .toList()
        }
    }

    override suspend fun getAllDesignFamilies(chainId: ChainId): Result<List<TattooFamily>> {
        return remoteStorageDataSource.queryCatching(chainId) {
            metadata.proofOfInk.designFamilies.entries()
                .values.toList()
        }
    }

    override suspend fun getAllCommittedTattoos(chainId: ChainId): Result<Set<DesignedTattooFlatId>> {
        return remoteStorageDataSource.queryCatching(chainId) {
            metadata.proofOfInk.committedDesigns.keys().toSet()
        }
    }

    override suspend fun getDesignFamily(chainId: ChainId, familyIndex: TattooFamilyIndex): Result<TattooFamily?> {
        return remoteStorageDataSource.queryCatching(chainId) {
            metadata.proofOfInk.designFamilies.query(familyIndex)
        }
    }

    override suspend fun getTattooFamilyMetadata(familyId: ByteArray): Result<TattooFamilyMetadata> {
        return tattooFamilyMetadataFetcher.getMetadata(familyId)
    }

    override fun subscribePendingInvites(
        chainId: ChainId,
        inviter: AccountId,
        invitee: AccountId
    ): Flow<Boolean> {
        return remoteStorageDataSource.subscribe(chainId) {
            metadata.proofOfInk.pendingInvites.observe(inviter.value, invitee.value)
        }.map { it === Unit }
    }

    override suspend fun flakeOut(chain: Chain): Result<Unit> {
        return extrinsicService.submitExtrinsicAndAwaitExecution(
            chain = chain,
            origin = proofOfInkOrigins.foreground.postApplyOrigin(chain)
        ) {
            proofOfInk.flakeout()
        }.flattenExecutionFailure()
            .coerceToUnit()
    }

    private suspend fun RuntimeCallsApi.candidacyDeposit(): Balance {
        return call(
            section = "ProofOfInkApi",
            method = "candidacy_deposit",
            arguments = emptyMap(),
            returnBinding = ::bindBalance
        )
    }
}
