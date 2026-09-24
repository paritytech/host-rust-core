package io.paritytech.polkadotapp.feature_products_impl.domain.truapi

import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.AccountSecretsStorage
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.requireMetaAccountPassphrase
import io.paritytech.polkadotapp.feature_usernames_api.domain.usecase.UsernameOfAccountUseCase
import kotlinx.coroutines.withTimeoutOrNull
import timber.log.Timber
import javax.inject.Inject
import kotlin.time.Duration.Companion.seconds

/** Secret material and display identity for the core's wallet-local session. */
class TrUAPILocalSession(
    val secret: ByteArray,
    val liteUsername: String?,
)

/**
 * Resolves the wallet-local signing session the Rust core runs on.
 *
 * Until SSO pairing moves into the core (truapi#334) the core has no session of
 * its own, and without one it can hold no keys — so every account and signing
 * call fails regardless of what the user approves. iOS activates the same local
 * session, which is why signing works there.
 *
 * The secret is raw BIP-39 entropy because the core derives the session's root
 * and identity keypairs from it directly; handing it anything derived would give
 * the same recovery phrase different product accounts than iOS derives.
 */
class TrUAPILocalSessionSource @Inject constructor(
    private val accountRepository: AccountRepository,
    private val accountSecretsStorage: AccountSecretsStorage,
    private val usernameOfAccountUseCase: UsernameOfAccountUseCase,
) {
    suspend fun resolve(): Result<TrUAPILocalSession> = runCatching {
        val account = accountRepository.getWalletAccount()

        TrUAPILocalSession(
            secret = accountSecretsStorage.requireMetaAccountPassphrase(account.id).entropy,
            liteUsername = resolveLiteUsername(),
        )
    }

    /** Bounded: a People-chain read that never emits must not hold the runtime boot. */
    private suspend fun resolveLiteUsername(): String? {
        val username = withTimeoutOrNull(LITE_USERNAME_LOOKUP_TIMEOUT) { usernameOfAccountUseCase.getUsername() }
            ?: return null.also {
                Timber.w("TrUAPI local session: lite username lookup did not answer in time; booting without one")
            }
        return username.getOrNull()?.liteUsername?.getDisplayUsername()
    }

    private companion object {
        val LITE_USERNAME_LOOKUP_TIMEOUT = 5.seconds
    }
}
