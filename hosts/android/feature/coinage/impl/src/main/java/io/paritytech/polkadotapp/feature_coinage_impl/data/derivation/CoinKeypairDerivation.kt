package io.paritytech.polkadotapp.feature_coinage_impl.data.derivation

import io.novasama.substrate_sdk_android.encrypt.EncryptionType
import io.novasama.substrate_sdk_android.encrypt.junction.SubstrateJunctionDecoder
import io.novasama.substrate_sdk_android.encrypt.keypair.Keypair
import io.novasama.substrate_sdk_android.encrypt.keypair.substrate.Sr25519Keypair
import io.novasama.substrate_sdk_android.encrypt.keypair.substrate.Sr25519SubstrateKeypairFactory
import io.novasama.substrate_sdk_android.encrypt.keypair.substrate.SubstrateKeypairFactory
import io.novasama.substrate_sdk_android.encrypt.seed.substrate.SubstrateSeedFactory
import io.paritytech.polkadotapp.chains.util.deriveSeed32
import io.paritytech.polkadotapp.common.domain.model.intoAccountId
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.AccountSecretsStorage
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.requireMetaAccountPassphrase
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.DerivationIndex
import javax.inject.Inject

interface CoinKeypairDerivation {
    suspend fun deriveKeypair(derivationIndex: DerivationIndex): Keypair

    suspend fun deriveKeypairs(derivationIndices: List<DerivationIndex>): List<Keypair>
}

class RealCoinKeypairDerivation @Inject constructor(
    private val accountRepository: AccountRepository,
    private val accountSecretsStorage: AccountSecretsStorage,
) : CoinKeypairDerivation {
    override suspend fun deriveKeypair(derivationIndex: DerivationIndex): Keypair {
        val accountId = accountRepository.getWalletAccount().id
        val mnemonic = accountSecretsStorage.requireMetaAccountPassphrase(accountId)

        val path = getDefaultPurseDerivation(derivationIndex)

        val seedResult = SubstrateSeedFactory.deriveSeed32(mnemonic.words, password = null)
        val keypair = SubstrateKeypairFactory.generate(EncryptionType.SR25519, seedResult.seed, path)

        return keypair
    }

    override suspend fun deriveKeypairs(derivationIndices: List<DerivationIndex>): List<Keypair> {
        val accountId = accountRepository.getWalletAccount().id
        val mnemonic = accountSecretsStorage.requireMetaAccountPassphrase(accountId)
        val seedResult = SubstrateSeedFactory.deriveSeed32(mnemonic.words, password = null)

        val pathBase = coinageDefaultPurseDerivationBase()
        val baseCoinageKeypair = SubstrateKeypairFactory.generate(EncryptionType.SR25519, seedResult.seed, pathBase)
            as Sr25519Keypair

        return derivationIndices.map { derivationIndex ->
            val itemSegment = itemDerivationSegment(derivationIndex)
            val junction = SubstrateJunctionDecoder.decode(itemSegment).junctions.first()
            Sr25519SubstrateKeypairFactory.deriveChild(baseCoinageKeypair, junction)
        }
    }

    private fun getDefaultPurseDerivation(item: Int): String = coinageDerivation(CoinageDerivationDefaults.COINAGE_MAIN_PURSE_INDEX, CoinageDerivationDefaults.COINAGE_PAGE_INDEX, item)

    private fun coinageDefaultPurseDerivationBase(): String = coinageDerivationBase(CoinageDerivationDefaults.COINAGE_MAIN_PURSE_INDEX, CoinageDerivationDefaults.COINAGE_PAGE_INDEX)

    @Suppress("SameParameterValue")
    private fun coinageDerivation(purse: Long, page: Int, item: Int): String {
        return coinageDerivationBase(purse, page) + itemDerivationSegment(item)
    }

    private fun itemDerivationSegment(item: Int): String {
        return "/$item"
    }

    private fun coinageDerivationBase(purse: Long, page: Int): String {
        return "//coinage//$purse//$page"
    }
}

suspend fun CoinKeypairDerivation.getDerivedAccountId(derivationIndex: DerivationIndex) = deriveKeypair(derivationIndex).publicKey.intoAccountId()

suspend fun CoinKeypairDerivation.getDerivedAccountIds(derivationIndices: List<DerivationIndex>) =
    deriveKeypairs(derivationIndices).map { it.publicKey.intoAccountId() }
