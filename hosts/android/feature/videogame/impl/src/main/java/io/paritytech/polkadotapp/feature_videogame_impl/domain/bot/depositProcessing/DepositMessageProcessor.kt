package io.paritytech.polkadotapp.feature_videogame_impl.domain.bot.depositProcessing

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainAssetWithAmount
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.withAsset
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_balances_api.data.repository.BalanceRepository
import io.paritytech.polkadotapp.feature_balances_api.data.repository.observeBalanceHoldById
import io.paritytech.polkadotapp.feature_balances_api.domain.model.BalanceHoldId
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.CandidateDepositAssetProvider
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotContext
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotMessageProcessor
import io.paritytech.polkadotapp.feature_tokens_api.domain.ChainAssetProvider
import io.paritytech.polkadotapp.feature_videogame_impl.domain.bot.messages.deposit.DepositAddedRenderer
import io.paritytech.polkadotapp.feature_videogame_impl.domain.bot.messages.deposit.model.DepositContent
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import javax.inject.Inject

class DepositMessageProcessor @Inject constructor(
    @param:CandidateDepositAssetProvider private val depositAssetProvider: ChainAssetProvider,
    private val accountRepository: AccountRepository,
    private val balanceRepository: BalanceRepository,
) : ChatBotMessageProcessor {
    private companion object {
        val DEPOSIT_HOLD_ID = BalanceHoldId("Game", "PlayGame")
    }

    context(chatBotContext: ChatBotContext)
    override fun launchSendingMessages() {
        chatBotContext.scope.launch {
            handleDepositHoldMessage()
        }
    }

    context(chatBotContext: ChatBotContext)
    private suspend fun handleDepositHoldMessage() {
        val chain = depositAssetProvider.chain()
        val candidateAccount = accountRepository.getCandidateAccount()
        val candidateAccountId = candidateAccount.accountIdIn(chain)

        var hadNoHoldPreviously = false

        observeGameDepositHold(chain, depositAssetProvider.asset(), candidateAccountId)
            .collect { currentHold ->
                if (hadNoHoldPreviously && currentHold != null) {
                    chatBotContext.sendCustomMessage(
                        content = DepositContent(
                            asset = DepositContent.Asset(chain.id, currentHold.chainAsset.id),
                            amount = currentHold.amount
                        ),
                        rendererId = DepositAddedRenderer.ID,
                    )
                }

                hadNoHoldPreviously = currentHold == null
            }
    }

    context(scope: ComputationalScope)
    private fun observeGameDepositHold(chain: Chain, asset: Chain.Asset, candidateAccountId: AccountId): Flow<ChainAssetWithAmount?> {
        return balanceRepository.observeBalanceHoldById(chain.id, candidateAccountId, DEPOSIT_HOLD_ID)
            .map { gameDepositHold ->
                gameDepositHold?.amount?.withAsset(asset)
            }
    }
}
