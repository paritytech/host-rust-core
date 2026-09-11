package io.paritytech.polkadotapp.tools_push_notifications_impl.data.network.models

import androidx.annotation.Keep

@Keep
data class NotifyResponse(
    val errors: List<Error>,
    val failed: Int,
    val messageId: String,
    val platform: String,
    val sent: Int,
    val success: Boolean
) {
    @Keep
    data class Error(
        val device: String,
        val response: Response?,
        val status: Int
    ) {
        @Keep
        data class Response(
            val reason: String
        )
    }
}
