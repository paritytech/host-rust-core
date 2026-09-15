package io.paritytech.polkadotapp.app.root.presentation.root

import io.paritytech.polkadotapp.common.presentation.navigation.ReturnableRouter
import io.paritytech.polkadotapp.feature_products_api.presentation.SpaBrowserPayload
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.gameResults.GameResultsPayload

interface RootRouter : ReturnableRouter {
    fun openClaimUsername()

    fun openMain()

    fun openScanner()

    fun openActiveProduct()

    fun openDebugMenu()

    fun openVideoGame()

    fun openProductBotsManagement()

    fun openSpaBrowser(payload: SpaBrowserPayload)

    /** Debug-only — bypasses the game lifecycle. */
    fun openSimulatedGameResults(payload: GameResultsPayload)
}
