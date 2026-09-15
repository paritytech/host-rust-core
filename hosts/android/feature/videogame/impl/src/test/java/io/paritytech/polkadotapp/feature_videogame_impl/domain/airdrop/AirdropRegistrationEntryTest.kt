package io.paritytech.polkadotapp.feature_videogame_impl.domain.airdrop

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchAlias
import io.paritytech.polkadotapp.common.domain.model.intoAccountId
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAccountOrPerson
import junit.framework.TestCase.assertTrue
import org.junit.Test

/**
 * The Alias ring proof signs the player's SCALE `RegistrationEntry`; the tag bytes come from
 * `pallets/airdrop::RegistrationEntry` (`Alias` = 0x00, `Account` = 0x01). A wrong tag means the
 * on-chain VRF message mismatches and the sign-up is rejected.
 */
class AirdropRegistrationEntryTest {
    @Test
    fun `alias entry is 0x00 plus the alias bytes`() {
        val alias = ByteArray(32) { 7 }
        val key = OnChainAccountOrPerson.Person(BandersnatchAlias(alias))

        val entry = key.toAirdropRegistrationEntryBytes()

        assertTrue(entry.contentEquals(byteArrayOf(0x00) + alias))
    }

    @Test
    fun `account entry is 0x01 plus the account id bytes`() {
        val accountId = ByteArray(32) { 9 }
        val key = OnChainAccountOrPerson.Account(accountId.intoAccountId())

        val entry = key.toAirdropRegistrationEntryBytes()

        assertTrue(entry.contentEquals(byteArrayOf(0x01) + accountId))
    }
}
