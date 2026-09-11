package io.paritytech.polkadotapp.feature_products_impl.presentation.compose

import androidx.compose.runtime.compositionLocalOf
import io.paritytech.polkadotapp.feature_products_api.model.JsUiEvent

typealias JsUiEventHandler = (actionId: String, eventType: JsUiEvent.Type) -> Unit

val LocalJsEventHandler = compositionLocalOf<JsUiEventHandler> { { _, _ -> } }
