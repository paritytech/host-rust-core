package io.paritytech.polkadotapp.feature_people_api.data.storage

import io.paritytech.polkadotapp.feature_people_api.domain.invitation.DimName
import io.paritytech.polkadotapp.feature_people_api.domain.invitation.IssuedInvitation
import kotlinx.coroutines.flow.Flow

/**
 * Stores [IssuedInvitation] — a complete, issued invitation by the server. Persisted across app
 * restarts so that retries after backend success can reuse the same ticket without burning quota.
 * Cleared via [clearIssuedInvitation] at well-defined terminal points (chain accept / chain reject).
 * Higher-level primitives like `GameInvitationUseCase` are still the preferred entry point —
 * this interface is mostly internal plumbing.
 */
interface InvitationStorage {
    fun setIssuedInvitation(invitation: IssuedInvitation)

    fun getIssuedInvitation(dim: DimName): IssuedInvitation?

    fun subscribeIssuedInvitation(dim: DimName): Flow<IssuedInvitation?>

    fun clearIssuedInvitation(dim: DimName)
}
