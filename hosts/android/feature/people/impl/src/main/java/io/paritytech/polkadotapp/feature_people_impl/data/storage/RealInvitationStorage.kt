package io.paritytech.polkadotapp.feature_people_impl.data.storage

import com.google.gson.Gson
import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import io.paritytech.polkadotapp.feature_people_api.data.storage.InvitationStorage
import io.paritytech.polkadotapp.feature_people_api.domain.invitation.DimName
import io.paritytech.polkadotapp.feature_people_api.domain.invitation.IssuedInvitation
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

private const val ISSUED_INVITATION_KEY_PREFIX = "IssuedInvitation.Dim"

internal class RealInvitationStorage @Inject constructor(
    private val preferences: Preferences,
    private val gson: Gson,
) : InvitationStorage {
    override fun setIssuedInvitation(invitation: IssuedInvitation) {
        val serializedInvitation = gson.toJson(invitation)
        preferences.putString(createKey(invitation.dim), serializedInvitation)
    }

    override fun getIssuedInvitation(dim: DimName): IssuedInvitation? {
        val serializedInvitation = preferences.getString(createKey(dim)) ?: return null
        return gson.fromJson(serializedInvitation, IssuedInvitation::class.java)
    }

    override fun subscribeIssuedInvitation(dim: DimName): Flow<IssuedInvitation?> {
        return preferences.stringFlow(createKey(dim))
            .map { serializedInvitation ->
                serializedInvitation?.let { gson.fromJson(it, IssuedInvitation::class.java) }
            }
    }

    override fun clearIssuedInvitation(dim: DimName) {
        preferences.putString(createKey(dim), null)
    }

    private fun createKey(dim: DimName): String = "$ISSUED_INVITATION_KEY_PREFIX${dim.value}"
}
