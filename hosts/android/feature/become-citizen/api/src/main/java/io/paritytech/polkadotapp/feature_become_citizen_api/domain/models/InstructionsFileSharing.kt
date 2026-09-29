package io.paritytech.polkadotapp.feature_become_citizen_api.domain.models

import android.net.Uri
import io.paritytech.polkadotapp.common.utils.InformationSize

class InstructionsFileSharing(
    val uri: Uri,
    val size: InformationSize,
    val mimeType: String
)
