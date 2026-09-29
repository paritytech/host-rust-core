package io.paritytech.polkadotapp.feature_people_impl.data.network

import io.paritytech.polkadotapp.feature_people_impl.data.network.model.DimTicketRequest
import io.paritytech.polkadotapp.feature_people_impl.data.network.model.DimTicketResponse
import io.paritytech.polkadotapp.tools_jwt_auth_api.CallWithBearerToken
import retrofit2.http.Body
import retrofit2.http.POST

internal interface InvitationTicketNetworkApi {
    @CallWithBearerToken
    @POST("api/v1/invitation-ticket/claim")
    suspend fun issueDimTicket(@Body request: DimTicketRequest): DimTicketResponse
}
