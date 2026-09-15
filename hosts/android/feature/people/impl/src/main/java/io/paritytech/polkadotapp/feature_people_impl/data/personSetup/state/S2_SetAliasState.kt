package io.paritytech.polkadotapp.feature_people_impl.data.personSetup.state

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.chains.util.Modules
import io.paritytech.polkadotapp.common.data.worker.stateMachine.WorkerStateMachineState
import io.paritytech.polkadotapp.common.data.worker.stateMachine.error.TransitionDidNotSucceedException
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_members_api.data.model.ringIndex
import io.paritytech.polkadotapp.feature_people_api.data.AliasContextProvider
import io.paritytech.polkadotapp.feature_people_api.data.repository.PersonIdRepository
import io.paritytech.polkadotapp.feature_people_api.data.repository.getPersonIdOrThrow
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import io.paritytech.polkadotapp.feature_people_impl.data.model.isAliasUpToDate
import io.paritytech.polkadotapp.feature_people_impl.data.personSetup.PersonSetupDataSource
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicExecutionResult
import io.paritytech.polkadotapp.feature_transactions.api.data.isModuleError
import io.paritytech.polkadotapp.feature_transactions.api.data.isOk
import timber.log.Timber

class SetAliasState(
    private val accountRepository: AccountRepository,
    private val personIdRepository: PersonIdRepository,
    private val stateFactory: PersonSetupStateFactory,
    private val assignableContexts: Set<AliasContextProvider>,
    override val params: Params
) : PersonSetupNonTerminalState(), WorkerStateMachineState.WithParams<SetAliasState.Params> {
    companion object {
        val ID = "SetAliasState"
    }

    override val id = ID

    data class Params(val lastAssignedIndex: Int) {
        companion object {
            fun initial(): Params {
                return Params(lastAssignedIndex = -1)
            }

            fun intermediate(lastAssignedIndex: Int): Params {
                require(lastAssignedIndex >= 0) {
                    "lastAssignedIndex cannot be negative. Use initial for the initial params"
                }

                return Params(lastAssignedIndex)
            }
        }
    }

    private suspend fun resolveSortedContexts(): List<BandersnatchContext> {
        return assignableContexts
            .map { it.context() }
            .sortedWith(DataByteArray.compareByBytes(unsigned = true) { it.value })
    }

    context(transition: PersonSetupState.Transition)
    override suspend fun performNonTerminalTransition(): Result<PersonSetupState> {
        val personId = personIdRepository.getPersonIdOrThrow()

        return assignAlias(
            sortedContexts = resolveSortedContexts(),
            contextIndex = params.lastAssignedIndex + 1,
            personId = personId
        )
    }

    context(transition: PersonSetupState.Transition)
    private suspend fun assignAlias(
        sortedContexts: List<BandersnatchContext>,
        contextIndex: Int,
        personId: PersonId
    ): Result<PersonSetupState> {
        val chain = transition.dataSource.peopleChain

        val context = sortedContexts[contextIndex]

        val aliasAccount = accountRepository.getAliasAccount(context)
        val aliasAccountId = aliasAccount.accountIdIn(chain)

        // Alias is already assigned - we have missed result of previous setAlias. Move to the next state immediately
        if (transition.dataSource.hasUpToDateAlias(aliasAccountId, personId)) {
            Timber.d("Found existing up-to-date alias. Skipping set alias for ${context.stringValue}")

            return Result.success(createNextState(sortedContexts, contextIndex))
        }

        return transition.dataSource.setAlias(context, aliasAccountId)
            .mapCatching { executionResult ->
                if (executionResult.canContinue()) {
                    createNextState(sortedContexts, contextIndex)
                } else {
                    throw TransitionDidNotSucceedException(executionResult.toString())
                }
            }
    }

    private suspend fun PersonSetupDataSource.hasUpToDateAlias(
        aliasAccountId: AccountId,
        personId: PersonId,
    ): Boolean {
        val alias = getRegisteredAlias(aliasAccountId) ?: return false
        val personRecord = getPersonRecord(personId)
        val memberRecord = getMemberRecord(personRecord.key) ?: return false

        val ringRoot = getRingRoot(alias.ring)

        val ringMatches = alias.ring == memberRecord.ringIndex
        val upToDateInRing = ringRoot.isAliasUpToDate(alias)

        return ringMatches && upToDateInRing
    }

    private fun createNextState(
        sortedContexts: List<BandersnatchContext>,
        justAssignedContextIndex: Int
    ): PersonSetupState {
        return if (justAssignedContextIndex == sortedContexts.lastIndex) {
            stateFactory.setPersonalIdAccount()
        } else {
            stateFactory.setAliasState(Params.intermediate(justAssignedContextIndex))
        }
    }

    private fun ExtrinsicExecutionResult.canContinue(): Boolean {
        // Attempt to set alias after successful previous attempt will result in "AccountInUse" error
        // https://github.com/paritytech/individuality/blob/132421e16d85535afe570a0a32feaecfb5c8e5f4/substrate/frame/people/src/lib.rs#L421
        return outcome.isOk() || outcome.isModuleError(Modules.PEOPLE, "AccountInUse")
    }
}
