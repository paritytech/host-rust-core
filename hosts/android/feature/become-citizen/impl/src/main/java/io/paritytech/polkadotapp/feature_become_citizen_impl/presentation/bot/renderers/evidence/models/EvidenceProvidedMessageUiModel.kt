package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.renderers.evidence.models

import android.net.Uri
import androidx.compose.runtime.Immutable
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceType

@Immutable
data class EvidenceProvidedMessageUiModel(
    val uri: Uri? = null,
    val providingState: EvidenceProvidingState? = null,
    val evidenceType: EvidenceType
)
