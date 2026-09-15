package io.paritytech.polkadotapp.feature_upgrade_username_impl.domain.usecase

import io.paritytech.polkadotapp.common.utils.flowOfAll
import io.paritytech.polkadotapp.feature_people_api.domain.useCase.PersonStatusUseCase
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.model.UpgradeToFullUsernameState
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.usecase.ReadyToUpgradeUsernameUseCase
import io.paritytech.polkadotapp.feature_upgrade_username_impl.data.ResourcesContextProvider
import io.paritytech.polkadotapp.feature_usernames_api.domain.usecase.UsernameOfAccountUseCase
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.filterNotNull
import javax.inject.Inject

class RealReadyToUpgradeUsernameUseCase @Inject constructor(
    private val personStatusUseCase: PersonStatusUseCase,
    private val usernameOfAccountUseCase: UsernameOfAccountUseCase,
    private val resourcesContextProvider: ResourcesContextProvider
) : ReadyToUpgradeUsernameUseCase {
    override operator fun invoke() = flowOfAll {
        combine(
            personStatusUseCase.canUseAliasFlow(resourcesContextProvider.context()),
            usernameOfAccountUseCase().filterNotNull()
        ) { canUseResourcesAlias, stored ->
            val fullUsername = stored.fullUsername
            when {
                !stored.isOnChain || !canUseResourcesAlias -> UpgradeToFullUsernameState.NotReady
                fullUsername == null -> UpgradeToFullUsernameState.Ready(stored.liteUsername)
                else -> UpgradeToFullUsernameState.Completed(stored.liteUsername, fullUsername)
            }
        }
    }
}
