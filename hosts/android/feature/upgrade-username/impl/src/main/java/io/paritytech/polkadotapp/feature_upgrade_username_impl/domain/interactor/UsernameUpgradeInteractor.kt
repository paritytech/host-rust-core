package io.paritytech.polkadotapp.feature_upgrade_username_impl.domain.interactor

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.common.utils.coerceToUnit
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getWalletAccountIdIn
import io.paritytech.polkadotapp.feature_dotns_gateway_api.data.repository.DotNsGatewayRepository
import io.paritytech.polkadotapp.feature_dotns_gateway_api.domain.model.DotNsLink
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.model.UpgradeUsernameAvailabilityState
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.usecase.CheckUsernameAvailabilityUseCase
import io.paritytech.polkadotapp.feature_usernames_api.data.LocalFullUsernameStorage
import io.paritytech.polkadotapp.feature_usernames_api.domain.model.Username
import io.paritytech.polkadotapp.feature_usernames_api.domain.usecase.UsernameOfAccountUseCase
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import javax.inject.Inject

interface UsernameUpgradeInteractor {
    suspend fun liteUsername(): Username

    suspend fun upgrade(username: String): Result<Unit>

    suspend fun checkUsernameAvailable(username: String): Result<UpgradeUsernameAvailabilityState>
}

class RealUsernameUpgradeInteractor @Inject constructor(
    knownChains: KnownChains,
    private val chainRegistry: ChainRegistry,
    private val accountRepository: AccountRepository,
    private val dotNsGatewayRepository: DotNsGatewayRepository,
    private val usernameOfAccountUseCase: UsernameOfAccountUseCase,
    private val localFullUsernameStorage: LocalFullUsernameStorage,
    private val checkUsernameAvailabilityUseCase: CheckUsernameAvailabilityUseCase
) : UsernameUpgradeInteractor {
    private val chainId = knownChains.assetHub

    override suspend fun liteUsername() = usernameOfAccountUseCase().filterNotNull().map { it.liteUsername }.first()

    override suspend fun upgrade(username: String): Result<Unit> {
        val accountId = accountRepository.getWalletAccountIdIn(chainRegistry.getChain(chainId))
        val link = DotNsLink.LiteUsername(liteUsername().getDisplayUsername())

        return dotNsGatewayRepository.registerName(
            who = accountId,
            label = username,
            link = link
        )
            .map { localFullUsernameStorage.saveValue(Username.fromParts(username, null)) }
            .coerceToUnit()
    }

    override suspend fun checkUsernameAvailable(username: String) = checkUsernameAvailabilityUseCase(username)
}
