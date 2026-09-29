package io.paritytech.polkadotapp.feature_become_citizen_api.domain.models

enum class EvidenceUploadingFailureReason {
    NO_STORAGE_AUTHORIZATION,
    STORAGE_CAPACITY_EXCEEDED,
    STORAGE_EXPIRED,
    NO_ALLOCATION
}
