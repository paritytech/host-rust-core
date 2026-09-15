package io.paritytech.polkadotapp.feature_become_citizen_impl.data.storage

import io.novasama.substrate_sdk_android.scale.EncodableStruct
import io.novasama.substrate_sdk_android.scale.Schema
import io.novasama.substrate_sdk_android.scale.byteArray
import io.novasama.substrate_sdk_android.scale.compactInt
import io.novasama.substrate_sdk_android.scale.toHexString
import io.paritytech.polkadotapp.chains.util.invoke
import io.paritytech.polkadotapp.common.data.storage.preferences.encrypted.EncryptedPreferences
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models.ReferralTicket
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models.ReferralTicketOrigin
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId.Companion.intoPersonId
import jakarta.inject.Inject
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext

interface ReferralTicketsStorage {
    suspend fun saveTicket(origin: ReferralTicketOrigin, referralTicket: ReferralTicket)

    suspend fun getSavedTicket(origin: ReferralTicketOrigin): ReferralTicket?

    fun removeSavedTicket(origin: ReferralTicketOrigin)

    suspend fun hasSavedTicket(origin: ReferralTicketOrigin): Boolean

    fun subscribeSavedTicket(origin: ReferralTicketOrigin): Flow<ReferralTicket?>
}

private const val PREFS_TICKETS_PREFIX = "ReferralTicketsStorage"

class EncryptedReferralTicketsStorage @Inject constructor(
    private val prefs: EncryptedPreferences,
    private val coroutineDispatchers: CoroutineDispatchers,
) : ReferralTicketsStorage {
    override suspend fun saveTicket(origin: ReferralTicketOrigin, referralTicket: ReferralTicket) = withContext(coroutineDispatchers.computation) {
        val key = createPrefsKey(origin)
        val value = serializeTicket(referralTicket)

        prefs.putEncryptedString(key, value)
    }

    override suspend fun getSavedTicket(origin: ReferralTicketOrigin): ReferralTicket? = withContext(coroutineDispatchers.computation) {
        val key = createPrefsKey(origin)
        val rawValue = prefs.getDecryptedString(key)

        rawValue?.let(::deserializeTicket)
    }

    override fun removeSavedTicket(origin: ReferralTicketOrigin) {
        prefs.removeKey(createPrefsKey(origin))
    }

    override suspend fun hasSavedTicket(origin: ReferralTicketOrigin): Boolean {
        return prefs.hasKey(createPrefsKey(origin))
    }

    override fun subscribeSavedTicket(origin: ReferralTicketOrigin): Flow<ReferralTicket?> {
        return prefs.decryptedStringFlow(createPrefsKey(origin))
            .map { rawValue ->
                rawValue?.let(::deserializeTicket)
            }
    }

    private fun createPrefsKey(origin: ReferralTicketOrigin): String {
        return "${PREFS_TICKETS_PREFIX}.${origin.prefsKeySuffix()}"
    }

    private fun ReferralTicketOrigin.prefsKeySuffix(): String {
        return when (this) {
            ReferralTicketOrigin.REFERRER -> "Referrer"
            ReferralTicketOrigin.REFEREE -> "Referee"
        }
    }

    private fun serializeTicket(ticket: ReferralTicket): String {
        return convertToStruct(ticket).toHexString()
    }

    private fun deserializeTicket(ticketRaw: String): ReferralTicket {
        return convertFromStruct(ReferralTicketSchema.read(ticketRaw))
    }
}

private object ReferralTicketSchema : Schema<ReferralTicketSchema>() {
    val entropy by byteArray()

    val referrer by compactInt()
}

private fun convertToStruct(referralTicket: ReferralTicket): EncodableStruct<ReferralTicketSchema> {
    return ReferralTicketSchema {
        it[referrer] = referralTicket.referrer.id
        it[entropy] = referralTicket.entropy
    }
}

private fun convertFromStruct(referralTicket: EncodableStruct<ReferralTicketSchema>): ReferralTicket {
    return ReferralTicket(
        referrer = referralTicket[ReferralTicketSchema.referrer].intoPersonId(),
        entropy = referralTicket[ReferralTicketSchema.entropy]
    )
}
