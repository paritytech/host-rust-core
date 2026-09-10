package io.paritytech.polkadotapp.feature_videogame_impl.data.telemetry.model

import androidx.annotation.Keep

@Keep
internal class VideoGameRegistrationDashboardRequest(
    val who: String,
    val usernameAccountId: String?,
    val username: String?,
    val timestamp: Long
)

@Keep
internal class VideoGameReportingDashboardRequest(
    val who: String,
    val peers: List<List<Peer>>,
    val timestamp: Long
) {
    @Keep
    class Peer(val id: String, val state: String)
}

@Keep
internal class VideoGameEndDashboardRequest(
    val who: String,
    val reports: List<List<Report>>,
    val timestamp: Long
) {
    @Keep
    class Report(val id: String, val verdict: String)
}
