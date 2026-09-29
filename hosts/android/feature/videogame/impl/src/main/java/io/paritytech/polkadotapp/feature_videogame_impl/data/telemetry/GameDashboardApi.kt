package io.paritytech.polkadotapp.feature_videogame_impl.data.telemetry

import io.paritytech.polkadotapp.feature_videogame_impl.data.telemetry.model.VideoGameEndDashboardRequest
import io.paritytech.polkadotapp.feature_videogame_impl.data.telemetry.model.VideoGameRegistrationDashboardRequest
import io.paritytech.polkadotapp.feature_videogame_impl.data.telemetry.model.VideoGameReportingDashboardRequest
import retrofit2.http.Body
import retrofit2.http.POST

internal interface GameDashboardApi {
    @POST("api/donate/registration")
    suspend fun registration(@Body body: VideoGameRegistrationDashboardRequest)

    @POST("api/donate/reporting")
    suspend fun reporting(@Body body: VideoGameReportingDashboardRequest)

    @POST("api/donate/end")
    suspend fun end(@Body body: VideoGameEndDashboardRequest)
}
