package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail

import android.os.Parcelable
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooIdParcelable
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.CaseType
import kotlinx.parcelize.Parcelize

@Parcelize
data class MediaEvidenceDetailPayload(
    val caseId: String,
    val caseType: CaseType,
    val evidenceHashHex: String,
    val viewOnly: Boolean,
    val tattooId: TattooIdParcelable,
    val tattooFamilyIdHex: String
) : Parcelable
