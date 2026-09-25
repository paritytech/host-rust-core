package io.paritytech.polkadotapp.feature_products_impl.domain.productPermissions

import io.paritytech.polkadotapp.feature_products_api.model.Product
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.data.repository.ProductRepository
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.ProductPermissionRepository
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.handlers.ProductPermissionHandler
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.models.ProductPermission
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.models.ProductPermissionStatus
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

class ProductPermissionsInteractor @Inject constructor(
    private val productRepository: ProductRepository,
    private val permissionRepository: ProductPermissionRepository,
    private val deviceCapabilityHandler: ProductPermissionHandler<ProductPermission.DeviceCapability>,
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
            revoke(productId, permissionStatus.permission)
        }
    }

    // Device capabilities go through their handler, which also drops what a revoked capability held.
    private suspend fun revoke(productId: ProductId, permission: ProductPermission) {
        when (permission) {
            is ProductPermission.DeviceCapability -> deviceCapabilityHandler.revoke(productId, permission)
            else -> permissionRepository.revoke(productId, permission)
        }
    }
}
