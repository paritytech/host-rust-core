package io.paritytech.polkadotapp.feature_products_impl.domain.truapi

import uniffi.truapi_server.NavigateDecision
import uniffi.truapi_server.parseNavigate
import javax.inject.Inject
import uniffi.truapi_server.PocketDeeplinkAction as NativePocketDeeplinkAction

enum class PocketDeeplinkAction { ADD, OPEN }

/** A `/-/pocket/<action>?card=<id>` deeplink as the core classifies it; [productHost] is the lower-cased dotNS name. */
data class PocketDeeplink(
    val productHost: String,
    val action: PocketDeeplinkAction,
    val cardId: String,
)

/**
 * Classifies through the core's `parse_navigate`, so every host reads a Pocket deeplink the same
 * way. Kept behind this adapter, like the host bridges, so a bindgen rename does not ripple.
 */
class PocketDeeplinkParser @Inject constructor() {
    fun parse(url: String): PocketDeeplink? {
        val decision = parseNavigate(url) as? NavigateDecision.Pocket ?: return null
        return PocketDeeplink(
            productHost = decision.identifier,
            action = when (decision.action) {
                NativePocketDeeplinkAction.ADD -> PocketDeeplinkAction.ADD
                NativePocketDeeplinkAction.OPEN -> PocketDeeplinkAction.OPEN
            },
            cardId = decision.cardId,
        )
    }
}
