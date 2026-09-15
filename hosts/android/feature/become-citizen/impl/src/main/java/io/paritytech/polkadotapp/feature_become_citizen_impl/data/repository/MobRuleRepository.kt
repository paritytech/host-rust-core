package io.paritytech.polkadotapp.feature_become_citizen_impl.data.repository

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.multiNetwork.withRuntime
import io.paritytech.polkadotapp.chains.util.mobRule
import io.paritytech.polkadotapp.chains.util.numberConstant
import javax.inject.Inject
import kotlin.time.Duration
import kotlin.time.Duration.Companion.hours

interface MobRuleRepository {
    suspend fun getMinimumReviewTime(chainId: ChainId): Result<Duration>

    suspend fun getMaximumReviewTime(chainId: ChainId): Result<Duration>
}

class RealMobRuleRepository @Inject constructor(
    val chainRegistry: ChainRegistry
) : MobRuleRepository {
    override suspend fun getMinimumReviewTime(chainId: ChainId): Result<Duration> {
        return getMobRuleDurationConstant(chainId, "MinCaseDuration")
    }

    override suspend fun getMaximumReviewTime(chainId: ChainId): Result<Duration> {
        return getMobRuleDurationConstant(chainId, "MaxVotingDuration")
    }

    private suspend fun getMobRuleDurationConstant(chainId: ChainId, name: String): Result<Duration> {
        return runCatching {
            chainRegistry.withRuntime(chainId) {
                // Mob rule duration constants are stored in hours format instead of number of blocks
                runtime.metadata.mobRule().numberConstant(name).toInt().hours
            }
        }
    }
}
