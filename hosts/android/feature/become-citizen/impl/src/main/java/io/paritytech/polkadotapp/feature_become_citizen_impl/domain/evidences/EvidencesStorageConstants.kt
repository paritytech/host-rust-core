package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences

import io.paritytech.polkadotapp.common.utils.InformationSize.Companion.megabytes

object EvidencesStorageConstants {
    val VIDEO_SIZE_LIMIT = 55.megabytes
    val PHOTO_SIZE_LIMIT = 5.megabytes
    val MIN_TOTAL_STORAGE_REQUIRED = 100.megabytes
}
