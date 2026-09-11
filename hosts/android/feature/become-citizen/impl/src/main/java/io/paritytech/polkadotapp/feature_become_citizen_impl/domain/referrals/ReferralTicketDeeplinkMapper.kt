package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.referrals

import io.novasama.substrate_sdk_android.extensions.fromHex
import io.novasama.substrate_sdk_android.extensions.toHexString
import io.paritytech.polkadotapp.common.presentation.deeplink.DeepLinkHandler.Companion.APP_SCHEME
import io.paritytech.polkadotapp.common.presentation.deeplink.DeepLinkHandler.Companion.WEB_HTTPS_SCHEME
import io.paritytech.polkadotapp.common.presentation.deeplink.DeepLinkHandler.Companion.WEB_HTTP_SCHEME
import io.paritytech.polkadotapp.common.presentation.deeplink.DeeplinkBuilder
import io.paritytech.polkadotapp.common.presentation.deeplink.getQueryParameterOrThrow
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models.ReferralTicket
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models.ReferralTicketDeeplink
import io.paritytech.polkadotapp.feature_become_citizen_impl.BuildConfig
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId.Companion.intoPersonId
import javax.inject.Inject

interface ReferralTicketDeeplinkMapper {
    fun canHandle(deeplink: ReferralTicketDeeplink): Boolean

    fun toDeeplink(referralTicket: ReferralTicket): ReferralTicketDeeplink

    fun toDeeplinkIfParamsAreEnough(params: Map<String, String>): ReferralTicketDeeplink?

    fun tryFromDeeplink(deeplink: ReferralTicketDeeplink): Result<ReferralTicket>
}

private const val INTERNAL_HOST = "referral"
private val WEB_HOST = BuildConfig.REFERRAL_WEB_HOST

private const val PARAM_REFERRAL_CODE = "referralCode"
private const val PARAM_REFERRER = "referrerId"

class RealReferralTicketDeeplinkMapper @Inject constructor() : ReferralTicketDeeplinkMapper {
    override fun canHandle(deeplink: ReferralTicketDeeplink): Boolean {
        return isValidInternal(deeplink) || isValidWeb(deeplink)
    }

    override fun toDeeplink(referralTicket: ReferralTicket): ReferralTicketDeeplink {
        return DeeplinkBuilder.startDeeplinkBuilder(APP_SCHEME)
            .authority(INTERNAL_HOST)
            .appendQueryParameter(PARAM_REFERRAL_CODE, referralTicket.entropy.toHexString())
            .appendQueryParameter(PARAM_REFERRER, referralTicket.referrer.id.toString())
            .build()
    }

    override fun toDeeplinkIfParamsAreEnough(params: Map<String, String>): ReferralTicketDeeplink? {
        return if (params.containsKey(PARAM_REFERRER) && params.containsKey(PARAM_REFERRAL_CODE)) {
            DeeplinkBuilder.startDeeplinkBuilder(APP_SCHEME)
                .authority(INTERNAL_HOST)
                .appendQueryParameter(PARAM_REFERRAL_CODE, params.getValue(PARAM_REFERRAL_CODE))
                .appendQueryParameter(PARAM_REFERRER, params.getValue(PARAM_REFERRER))
                .build()
        } else null
    }

    override fun tryFromDeeplink(deeplink: ReferralTicketDeeplink): Result<ReferralTicket> {
        return runCatching {
            val ticketEntropy = deeplink.getQueryParameterOrThrow(PARAM_REFERRAL_CODE).fromHex()
            val ticketReferrer = deeplink.getQueryParameterOrThrow(PARAM_REFERRER)

            ReferralTicket(
                referrer = ticketReferrer.toBigInteger().intoPersonId(),
                entropy = ticketEntropy
            )
        }
    }

    private fun isValidInternal(deeplink: ReferralTicketDeeplink): Boolean {
        return deeplink.scheme == APP_SCHEME && deeplink.authority == INTERNAL_HOST
    }

    private fun isValidWeb(deeplink: ReferralTicketDeeplink): Boolean {
        return (deeplink.scheme == WEB_HTTP_SCHEME || deeplink.scheme == WEB_HTTPS_SCHEME) && deeplink.authority == WEB_HOST
    }
}
