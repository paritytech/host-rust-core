package io.paritytech.polkadotapp.feature_web3summit_api.presentation

interface PostOnboardingFlow {
    /**
     * Decides the post-onboarding destination (main, W3S wait, or W3S SPA)
     * based on the W3S gate state, and performs the navigation.
     */
    suspend fun openPostOnboarding()
}
