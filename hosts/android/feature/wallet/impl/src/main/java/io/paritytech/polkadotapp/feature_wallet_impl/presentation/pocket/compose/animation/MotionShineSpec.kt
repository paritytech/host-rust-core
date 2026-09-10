package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.animation

internal data class MotionShineParameters(
    val intensity: Float,
    val dimming: Float,
    val width: Float,
    val length: Float,
    val center: Float
) {
    companion object {
        val DigitalDollarCard = MotionShineParameters(
            intensity = 0.5f,
            dimming = 0.7f,
            width = 0.3f,
            length = 0.8f,
            center = 0.3f
        )

        fun collectibles(isExpanded: Boolean) = MotionShineParameters(
            intensity = 0.08f,
            dimming = 0.17f,
            width = 0.1f,
            length = 0.5f,
            center = if (isExpanded) 0.5f else 0.25f
        )
    }
}
