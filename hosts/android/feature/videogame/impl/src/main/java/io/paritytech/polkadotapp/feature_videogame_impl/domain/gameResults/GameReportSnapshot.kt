package io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults

import javax.inject.Inject
import javax.inject.Singleton

/**
 * Captures state at report-submit time that the results screen still needs but which is gone
 * (or has moved) by the time results open:
 *  - [wasRegistered]: were we already a member just before the report (to tell "just became a
 *    member" from "was already one"); defaults to registered on the consumer side when absent,
 *    so a missing snapshot never produces a false celebration.
 *  - [playerCount]: the game's player count, only exposed on-chain while in `Reporting`. Fast
 *    Attendance (individuality PR #827) advances the game to `PlayerProcess` before results open,
 *    at which point `Reporting.playerCount` is null — so we snapshot it here while it's available.
 *
 * Captured in the vote interactor pre-report; read (not consumed) by the results interactor.
 * Overwritten on the next report.
 */
@Singleton
class GameReportSnapshot @Inject constructor() {
    data class ReportContext(val wasRegistered: Boolean, val playerCount: Int?)

    @Volatile
    private var captured: ReportContext? = null

    fun capture(wasRegistered: Boolean, playerCount: Int?) {
        captured = ReportContext(wasRegistered = wasRegistered, playerCount = playerCount)
    }

    fun current(): ReportContext? = captured
}
