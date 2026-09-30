package io.paritytech.polkadotapp.feature_products_impl.domain.productPermissions

import io.paritytech.polkadotapp.feature_products_api.domain.game.ProductGameReminder
import io.paritytech.polkadotapp.feature_products_api.model.Product
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.data.repository.ProductRepository
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.ProductPermissionRepository
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.models.DeviceCapabilityType
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.models.ProductPermission
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.models.ProductPermissionStatus
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

class ProductPermissionsInteractor @Inject constructor(
    private val productRepository: ProductRepository,
    private val permissionRepository: ProductPermissionRepository,
    private val productGameReminder: ProductGameReminder,
) {
    suspend fun getProduct(productId: ProductId): Product? {
        return productRepository.getProductById(productId)
    }

    fun observePermissions(productId: ProductId): Flow<List<ProductPermissionStatus>> {
        return permissionRepository.observeAllByProduct(productId)
    }

    suspend fun togglePermission(productId: ProductId, permissionStatus: ProductPermissionStatus) {
        if (permissionStatus.granted.not()) {
            permissionRepository.grant(productId, permissionStatus.permission)
        } else {
            permissionRepository.revoke(productId, permissionStatus.permission)
            if (permissionStatus.permission.remindsOfGames()) productGameReminder.cancel(productId)
        }
    }

    // A reminder rings through one of these, so revoking either drops it.
    private fun ProductPermission.remindsOfGames() = this is ProductPermission.DeviceCapability &&
        capability in setOf(DeviceCapabilityType.Alarm, DeviceCapabilityType.Notifications)
}
