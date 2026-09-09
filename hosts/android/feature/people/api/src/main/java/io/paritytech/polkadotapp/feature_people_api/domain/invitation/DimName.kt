package io.paritytech.polkadotapp.feature_people_api.domain.invitation

@JvmInline
value class DimName(val value: String) {
    companion object {
        // Intentionally non-empty. Feature modules attach DIM-specific values via
        // `val DimName.Companion.<name>`
    }
}
