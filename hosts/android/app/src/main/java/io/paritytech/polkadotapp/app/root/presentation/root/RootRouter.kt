package io.paritytech.polkadotapp.app.root.presentation.root

import io.paritytech.polkadotapp.common.presentation.navigation.ReturnableRouter
import io.paritytech.polkadotapp.feature_products_api.presentation.SpaBrowserPayload
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.gameResults.GameResultsPayload

interface RootRouter : ReturnableRouter {
    fun openClaimUsername()

    fun openMain()

    fun openAddContact()

    fun openActiveProduct()

    fun openDebugMenu()

    fun openIssueReport(screenshotPath: String)

    fun openVideoGame()

    fun openProductBotsManagement()

    /** Debug: draw a renderer tree served over HTTP at Pocket card size. */
    fun openPocketFacePreview()

    fun openSpaBrowser(payload: SpaBrowserPayload)

    /** Debug-only — bypasses the game lifecycle. */
    fun openSimulatedGameResults(payload: GameResultsPayload)
}
