@file:OptIn(ExperimentalContracts::class)

package io.paritytech.polkadotapp.feature_become_citizen_api.domain

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.common.domain.model.Timestamp
import io.paritytech.polkadotapp.common.utils.Fraction
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceType
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceUploadingFailureReason
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooId
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import kotlin.contracts.ExperimentalContracts
import kotlin.time.Duration

sealed interface TattooProgressState {
    sealed interface Started : TattooProgressState

    data object NotStarted : TattooProgressState

    // Declared intention to get a tattoo.  Deposit is taken or reference is used.
    data class Applied(val entropy: DataByteArray) : Started

    // Committed to a design and authorize the storage for (possibly just initial) evidence. Chain value is Selected
    data class Committed(val expiration: TattooCommitmentExpiration, val tattooId: TattooId) : Started

    data class UploadingEvidence(val evidenceType: EvidenceType, val status: Status) : Started {
        sealed interface Status {
            data object WaitingForStorageAllocation : Status
            data class UploadingInProgress(val progress: Fraction) : Status
            data object FinalizingUploading : Status
            data object WaitingForJudgement : Status
        }
    }

    data object RegisteringPerson : Started

    data class RecognizedPerson(
        val personId: PersonId,
        val activeReferrals: List<AccountId>,
        val banned: Boolean,
        val pendingReferralRewards: Int,
        val allowedReferralTickets: Int,
    ) : Started

    data class UnrecoverableFailure(val reason: EvidenceUploadingFailureReason) : Started

    // We can't parse actual state. Breaking change for API?
    data object Unknown : TattooProgressState
}

class TattooCommitmentExpiration(
    val expiresIn: Duration,
    val expiresAt: Timestamp,
    val hasExpired: Boolean
)
