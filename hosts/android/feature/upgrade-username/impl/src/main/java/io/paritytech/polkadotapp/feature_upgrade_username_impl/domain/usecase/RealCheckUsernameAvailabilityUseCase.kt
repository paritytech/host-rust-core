package io.paritytech.polkadotapp.feature_upgrade_username_impl.domain.usecase

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getWalletAccountIdIn
import io.paritytech.polkadotapp.feature_dotns_gateway_api.data.repository.DotNsGatewayRepository
import io.paritytech.polkadotapp.feature_dotns_gateway_api.domain.model.DotNsBaseNameAvailability
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.model.UpgradeUsernameAvailabilityState
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.usecase.CheckUsernameAvailabilityUseCase
import javax.inject.Inject

class RealCheckUsernameAvailabilityUseCase @Inject constructor(
    private val knownChains: KnownChains,
    private val chainRegistry: ChainRegistry,
    private val accountRepository: AccountRepository,
    private val dotNsGatewayRepository: DotNsGatewayRepository
) : CheckUsernameAvailabilityUseCase {
    override suspend fun invoke(username: String): Result<UpgradeUsernameAvailabilityState> {
        val accountId = accountRepository.getWalletAccountIdIn(chainRegistry.getChain(knownChains.assetHub))

        return dotNsGatewayRepository.getBaseNameAvailability(username, accountId)
            .map { it.toUpgradeState() }
    }

    private fun DotNsBaseNameAvailability.toUpgradeState(): UpgradeUsernameAvailabilityState {
        return when (this) {
            DotNsBaseNameAvailability.Free -> UpgradeUsernameAvailabilityState.Free
            DotNsBaseNameAvailability.ReservedByUs -> UpgradeUsernameAvailabilityState.ReservedByUs
            DotNsBaseNameAvailability.TakenByOther -> UpgradeUsernameAvailabilityState.NotAvailable
        }
    }
}
