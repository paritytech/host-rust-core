package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.deposit

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainAssetId
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainAssetWithAmount
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.withAmount
import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.common.utils.flowOfAll
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_balances_api.data.repository.BalanceRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

interface DepositTokensInteractor {
    suspend fun getCurrentAddress(chainId: ChainId): String

    suspend fun createTokenAmount(chainId: ChainId, assetId: ChainAssetId, planks: Balance): ChainAssetWithAmount

    fun subscribeBalanceIsEnough(chainId: ChainId, assetId: ChainAssetId, planks: Balance): Flow<Boolean>
}

class RealDepositTokensInteractor @Inject constructor(
    private val chainRegistry: ChainRegistry,
    private val accountRepository: AccountRepository,
    private val balanceRepository: BalanceRepository
) : DepositTokensInteractor {
    override suspend fun getCurrentAddress(chainId: ChainId): String {
        val chain = chainRegistry.getChain(chainId)
        return accountRepository.getCandidateAccount().addressIn(chain)
    }

    override suspend fun createTokenAmount(
        chainId: ChainId,
        assetId: ChainAssetId,
        planks: Balance
    ): ChainAssetWithAmount {
        val chain = chainRegistry.getChain(chainId)
        val asset = chain.assetsById.getValue(assetId)

        return asset.withAmount(planks)
    }

    override fun subscribeBalanceIsEnough(
        chainId: ChainId,
        assetId: ChainAssetId,
        planks: Balance
    ): Flow<Boolean> = flowOfAll {
        val account = accountRepository.getCandidateAccount()
        val chain = chainRegistry.getChain(chainId)
        val asset = chain.assetsById.getValue(assetId)

        balanceRepository.syncedTokenBalanceFlow(account.id, asset).map { currentBalance ->
            currentBalance.canReserve(planks)
        }
    }
}
