package io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.models

import kotlinx.serialization.Serializable

// This is a sealed class and not regular enum to match on-chain structure
@Serializable
sealed class ProofOfInkAllocation {
    @Serializable
    data object Initial : ProofOfInkAllocation()

    @Serializable
    data object InitDone : ProofOfInkAllocation()

    @Serializable
    data object Full : ProofOfInkAllocation()
}
