package io.paritytech.polkadotapp.feature_become_citizen_impl.data.signer.proofOfInk

import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.models.ProofOfInkCandidate
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.signer.proofOfInk.datasource.BackgroundPoIOriginsDataSource
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.signer.proofOfInk.datasource.ForegroundPoIOriginsDataSource
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.signer.proofOfInk.datasource.ProofOfInkOriginsDataSource
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

interface ProofOfInkOriginsFactory {
    /**
     * Default implementation of [ProofOfInkOrigins] that is usable in foreground
     */
    val foreground: ProofOfInkOrigins

    /**
     * Creates implementation of [ProofOfInkOrigins] that is usable in background workers
     */
    fun createBackground(candidateState: Flow<ProofOfInkCandidate?>): ProofOfInkOrigins
}

class RealProofOfInkOriginsFactory @Inject constructor(
    private val accountRepository: AccountRepository,
    foregroundDataSource: ForegroundPoIOriginsDataSource
) : ProofOfInkOriginsFactory {
    override val foreground: ProofOfInkOrigins = createOrigins(foregroundDataSource)

    override fun createBackground(candidateState: Flow<ProofOfInkCandidate?>): ProofOfInkOrigins {
        val dataSource = BackgroundPoIOriginsDataSource(candidateState)
        return createOrigins(dataSource)
    }

    private fun createOrigins(dataSource: ProofOfInkOriginsDataSource): ProofOfInkOrigins {
        return RealProofOfInkOrigins(
            accountRepository = accountRepository,
            dataSource = dataSource
        )
    }
}
