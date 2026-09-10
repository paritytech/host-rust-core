package io.paritytech.polkadotapp.feature_videogame_impl.domain.airdrop

import io.paritytech.polkadotapp.bandersnatch_crypto.intoBandersnatchContext
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.common.data.cache.CacheableDataConsistency
import io.paritytech.polkadotapp.common.utils.blake2b256
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.AccountSecretsStorage
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.getMetaAccountSr25519Keypair
import io.paritytech.polkadotapp.feature_members_api.data.repository.MembersRepository
import io.paritytech.polkadotapp.feature_people_api.domain.PeopleCollection
import io.paritytech.polkadotapp.feature_people_api.domain.PeopleMembershipProver
import io.paritytech.polkadotapp.feature_people_api.domain.toRingCollectionId
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults.AirdropEventId
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAccountOrPerson
import io.paritytech.polkadotapp.sr25519_vrf.Sr25519VrfSigner
import javax.inject.Inject

/**
 * Builds the `airdrop` VRF proof attached to game sign-up. The variant is dictated by the player's
 * ON-CHAIN recognition (the runtime enforces it via `Recognition::is_recognized`): recognized →
 * bandersnatch ring "Alias" proof at the current on-chain ring revision; non-recognized →
 * sr25519 "Account" VRF. The Alias proof signs the player's actual registration entry, so a
 * recognized player registering as an Account signs the Account entry form. Mirrors iOS
 * `AirdropProofFactory`.
 */
class AirdropProofFactory @Inject constructor(
    private val accountRepository: AccountRepository,
    private val accountSecretsStorage: AccountSecretsStorage,
    private val peopleMembershipProver: PeopleMembershipProver,
    private val membersRepository: MembersRepository,
) {
    suspend fun makeProof(
        chainId: ChainId,
        gameIndex: GameIndex,
        playerKey: OnChainAccountOrPerson,
        recognized: Boolean,
    ): Result<AirdropProof> {
        return if (recognized) makeAliasProof(chainId, gameIndex, playerKey) else makeAccountProof(gameIndex)
    }

    private suspend fun makeAccountProof(gameIndex: GameIndex): Result<AirdropProof> {
        val candidateId = accountRepository.getCandidateAccount().id
        val keypair = accountSecretsStorage.getMetaAccountSr25519Keypair(candidateId)
        // schnorrkel expects the full 96-byte keypair: secret (privateKey ++ nonce) ++ publicKey.
        val keypairBytes = keypair.privateKey + keypair.nonce + keypair.publicKey

        return Sr25519VrfSigner.sign(
            keypair = keypairBytes,
            transcriptLabel = AirdropVrfTranscript.LABEL,
            items = AirdropVrfTranscript.items(eventId(gameIndex), keypair.publicKey),
        ).map { signature ->
            AirdropProof.Account(preOutput = signature.preOutput, proof = signature.proof)
        }
    }

    private suspend fun makeAliasProof(
        chainId: ChainId,
        gameIndex: GameIndex,
        playerKey: OnChainAccountOrPerson,
    ): Result<AirdropProof> {
        // The message is the player's SCALE `RegistrationEntry` — the entry the runtime derives
        // from the sign-up origin; context = blake2b256("…/airdrop" ++ eventId).
        val message = playerKey.toAirdropRegistrationEntryBytes()
        val context = (AIRDROP_CONTEXT_BASE + eventId(gameIndex)).blake2b256().intoBandersnatchContext()

        return peopleMembershipProver.proofPersonMembership(
            message = message,
            context = context,
            chainId = chainId,
            peopleCollection = PeopleCollection.People,
        ).flatMap { membershipProof ->
            val ringIndex = membershipProof.ringIndex
            // Submit the CURRENT on-chain revision, not the local record's — they drift.
            membersRepository.getRingRoots(
                chainId = chainId,
                keys = listOf(PeopleCollection.People.toRingCollectionId() to ringIndex),
                consistency = CacheableDataConsistency.CONSISTENT_WITH_REMOTE,
            ).flatMap { roots ->
                val revision = roots.values.firstOrNull()?.revision
                    ?: return@flatMap Result.failure(AirdropProofError.MissingRingRevision)

                Result.success(
                    AirdropProof.Alias(
                        proof = membershipProof.proof.value,
                        ringIndex = ringIndex.value.toInt(),
                        revision = revision.value,
                    )
                )
            }
        }
    }

    private fun eventId(gameIndex: GameIndex): ByteArray = AirdropEventId.fromGameIndex(gameIndex).value.value

    private companion object {
        val AIRDROP_CONTEXT_BASE = "pop:polkadot.network/airdrop".toByteArray(Charsets.US_ASCII)
    }
}

/**
 * The SCALE encoding of the runtime's `RegistrationEntry` for this player key — the message the
 * Alias ring proof must sign. Tags from `pallets/airdrop`: `Alias { alias }` = 0x00,
 * `Account { account_id }` = 0x01.
 */
internal fun OnChainAccountOrPerson.toAirdropRegistrationEntryBytes(): ByteArray = when (this) {
    is OnChainAccountOrPerson.Person -> byteArrayOf(REGISTRATION_ENTRY_ALIAS_TAG) + alias.value
    is OnChainAccountOrPerson.Account -> byteArrayOf(REGISTRATION_ENTRY_ACCOUNT_TAG) + accountId.value
}

internal const val REGISTRATION_ENTRY_ALIAS_TAG: Byte = 0x00
internal const val REGISTRATION_ENTRY_ACCOUNT_TAG: Byte = 0x01
