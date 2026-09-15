package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.referrals

import android.content.Context
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.ReferralInstallHandler
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models.ReferralInstallResult
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.storage.ReferralInstallHandlerStorage
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

class RealReferralInstallHandler(
    private val context: Context,
    private val installReferrerHandleStorage: ReferralInstallHandlerStorage,
    private val referralTicketDeeplinkMapper: ReferralTicketDeeplinkMapper
) : ReferralInstallHandler {
    override suspend fun getResult(): ReferralInstallResult = suspendCoroutine { continuation ->
        if (installReferrerHandleStorage.isHandled()) {
            continuation.resume(ReferralInstallResult.AlreadyHandled)
        } else {
            val referrerClient = InstallReferrerClient.newBuilder(context).build()

            referrerClient.startConnection(
                object : InstallReferrerStateListener {
                    override fun onInstallReferrerSetupFinished(responseCode: Int) {
                        when (responseCode) {
                            InstallReferrerClient.InstallReferrerResponse.OK -> {
                                val params = extractParams(referrerClient.installReferrer.installReferrer)

                                referralTicketDeeplinkMapper.toDeeplinkIfParamsAreEnough(params)?.let {
                                    continuation.resume(ReferralInstallResult.DeeplinkExtracted(it))
                                } ?: continuation.resume(ReferralInstallResult.BadParams)
                            }

                            InstallReferrerClient.InstallReferrerResponse.FEATURE_NOT_SUPPORTED -> {
                                continuation.resume(ReferralInstallResult.NotSupported)
                            }

                            InstallReferrerClient.InstallReferrerResponse.SERVICE_UNAVAILABLE -> {
                                continuation.resume(ReferralInstallResult.ServiceUnavailable)
                            }
                        }

                        referrerClient.endConnection()
                        installReferrerHandleStorage.setHandled(true)
                    }

                    override fun onInstallReferrerServiceDisconnected() {
                        continuation.resume(ReferralInstallResult.ServiceDisconnected)
                    }
                }
            )
        }
    }

    private fun extractParams(query: String) = query
        .split("&")
        .associate { param ->
            val (key, value) = param.split("=")
            key to value
        }
}
