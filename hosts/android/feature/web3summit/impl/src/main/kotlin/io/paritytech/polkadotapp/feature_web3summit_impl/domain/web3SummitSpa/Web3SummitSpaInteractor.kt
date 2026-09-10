package io.paritytech.polkadotapp.feature_web3summit_impl.domain.web3SummitSpa

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.toSubstrateAddress
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.feature_account_api.domain.derivation.DerivationIndex32
import io.paritytech.polkadotapp.feature_products_api.domain.ProductAccountIdProvider
import io.paritytech.polkadotapp.feature_products_api.model.ProductAccountId
import io.paritytech.polkadotapp.feature_web3summit_impl.data.config.Web3SummitConfigProvider
import io.paritytech.polkadotapp.feature_web3summit_impl.data.contract.Web3SummitContractRepository
import io.paritytech.polkadotapp.feature_web3summit_impl.data.storage.PreferencesWeb3SummitVerifiedStorage
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import timber.log.Timber
import javax.inject.Inject
import kotlin.time.Duration.Companion.seconds

class Web3SummitSpaInteractor @Inject constructor(
    private val productAccountIdProvider: ProductAccountIdProvider,
    private val contractRepository: Web3SummitContractRepository,
    private val verifiedStorage: PreferencesWeb3SummitVerifiedStorage,
    private val configProvider: Web3SummitConfigProvider,
) {
    suspend fun awaitAttendanceConfirmed(): Result<Unit> {
        return configProvider.getConfig().flatMap { config ->
            val productAccountIdSpec = ProductAccountId(
                productId = config.productId.value,
                index = DerivationIndex32.default(),
            )
            productAccountIdProvider.deriveAccountId(productAccountIdSpec)
                .flatMap { pollUntilCheckedIn(it) }
        }
    }

    fun markVerifiedManually() {
        verifiedStorage.setVerified(true)
    }

    private suspend fun pollUntilCheckedIn(productAccountId: AccountId): Result<Unit> = runCatching {
        val address = productAccountId.toSubstrateAddress(42)

        while (currentCoroutineContext().isActive) {
            Timber.d("Polling isCheckedIn for $address...")

            val isCheckedIn = contractRepository.isCheckedIn(productAccountId).getOrNull() == true

            Timber.d("isCheckedIn=$isCheckedIn")

            if (isCheckedIn) {
                verifiedStorage.setVerified(true)
                return@runCatching
            }
            delay(POLL_INTERVAL)
        }
    }

    companion object {
        private val POLL_INTERVAL = 2.seconds
    }
}
