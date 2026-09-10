package io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models

import android.net.Uri
import io.novasama.substrate_sdk_android.encrypt.EncryptionType
import io.novasama.substrate_sdk_android.encrypt.mnemonic.Mnemonic
import io.novasama.substrate_sdk_android.encrypt.mnemonic.MnemonicCreator
import io.novasama.substrate_sdk_android.runtime.definitions.types.generics.MultiSignature
import io.paritytech.polkadotapp.chains.util.KeyPairGenerator
import io.paritytech.polkadotapp.chains.util.sign
import io.paritytech.polkadotapp.chains.util.signing.MessageSigningContext
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId

class ReferralTicket(
    val referrer: PersonId,
    val entropy: ByteArray,
) {
    val keypair by lazy {
        KeyPairGenerator.deriveSr25519From(MnemonicCreator.fromEntropy(entropy))
    }

    companion object {
        fun generateNew(referrer: PersonId): ReferralTicket {
            return ReferralTicket(
                referrer = referrer,
                entropy = KeyPairGenerator.randomEntropy(Mnemonic.Length.TWELVE)
            )
        }
    }

    fun toPublic(): ReferralTicketPublic {
        return ReferralTicketPublic(keypair.publicKey)
    }

    fun createReferralSignature(referee: AccountId): MultiSignature {
        val signature = keypair.sign(referee.value, MessageSigningContext.trustedContent())

        return MultiSignature(EncryptionType.SR25519, signature)
    }
}

class ReferralTicketPublic(val publicKey: ByteArray)

/**
 * Used to disambiguate saved tickets in the storage
 */
enum class ReferralTicketOrigin {
    /**
     * We are the referrer (the person generation the ticket)
     */
    REFERRER,

    /**
     * We are the referee (the person applying with a ticket)
     */
    REFEREE
}

typealias ReferralTicketDeeplink = Uri
