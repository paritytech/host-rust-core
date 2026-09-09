@file:OptIn(kotlin.time.ExperimentalTime::class)

package io.paritytech.polkadotapp.feature_people_impl.data.personSetup.state

import io.paritytech.polkadotapp.common.data.worker.stateMachine.WorkerStateMachineState.TransitionResult
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_members_api.domain.SelfIncludeEligibility
import io.paritytech.polkadotapp.feature_transactions.api.data.flattenExecutionFailure

class SelfIncludeState(
    private val stateFactory: PersonSetupStateFactory,
) : PersonSetupState {
    companion object {
        const val ID = "SelfInclude"
    }

    override val id = ID

    context(transition: PersonSetupState.Transition)
    override suspend fun performTransition(): TransitionResult<PersonSetupState> {
        val eligibility = runCatching { transition.dataSource.getCurrentEligibility() }
            .getOrElse { return TransitionResult.failure(it) }

        return when (eligibility) {
            is SelfIncludeEligibility.Eligible -> {
                val submission: Result<PersonSetupState> = transition.dataSource.submitSelfInclude(eligibility.callValidAt)
                    .flattenExecutionFailure()
                    .logFailure("self_include submission failed")
                    .map { stateFactory.awaitRingInclusion() }
                TransitionResult.TransitionPerformed(submission)
            }
            is SelfIncludeEligibility.Waiting -> TransitionResult.WaitUntil(eligibility.readyAt)
            SelfIncludeEligibility.NotEligible,
            SelfIncludeEligibility.SelfIncludeNotNeeded -> {
                TransitionResult.TransitionPerformed(Result.success(stateFactory.awaitRingInclusion()))
            }
        }
    }
}
