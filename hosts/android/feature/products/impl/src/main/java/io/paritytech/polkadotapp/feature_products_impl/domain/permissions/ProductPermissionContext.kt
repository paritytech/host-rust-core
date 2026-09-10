package io.paritytech.polkadotapp.feature_products_impl.domain.permissions

import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.models.PermissionDecision
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.models.ProductPermission
import kotlinx.coroutines.CompletableDeferred

class ProductPermissionContext(
    val productId: ProductId,
    val permissions: List<ProductPermission>,
) {
    private val result = CompletableDeferred<PermissionDecision>()

    fun deliver(decision: PermissionDecision) {
        result.complete(decision)
    }

    suspend fun awaitDecision(): PermissionDecision = result.await()
}
