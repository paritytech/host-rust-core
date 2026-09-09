package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.family.list

import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.TattooProgressState
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.candidateState.TattooProgressStateUseCase
import kotlin.random.Random

private val MockedProceduralEntropy = Random.nextBytes(32).toDataByteArray()

suspend fun TattooProgressStateUseCase.getProceduralTattooEntropyForCurrentState(): Result<DataByteArray> {
    return getTattooProgressState()
        .map { currentState ->
            if (currentState is TattooProgressState.Applied) {
                currentState.entropy
            } else {
                MockedProceduralEntropy
            }
        }
}
