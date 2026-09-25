package io.paritytech.polkadotapp.feature_products_impl.domain.productPermissions

import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.data.repository.ProductRepository
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.ProductPermissionRepository
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.handlers.ProductPermissionHandler
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.models.DeviceCapabilityType
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.models.ProductPermission
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.models.ProductPermissionStatus
import kotlinx.coroutines.runBlocking
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.mockito.Mockito.verifyNoInteractions

class ProductPermissionsInteractorTest {
    private val productRepository: ProductRepository = mock()
    private val permissionRepository: ProductPermissionRepository = mock()

    @Suppress("UNCHECKED_CAST")
    private val deviceCapabilityHandler: ProductPermissionHandler<ProductPermission.DeviceCapability> =
        mock(ProductPermissionHandler::class.java) as ProductPermissionHandler<ProductPermission.DeviceCapability>

    private val productId = ProductId.fromStoredValue("jollity.dot")
    private val alarm = ProductPermission.DeviceCapability(DeviceCapabilityType.Alarm)

    private val interactor = ProductPermissionsInteractor(
        productRepository = productRepository,
        permissionRepository = permissionRepository,
        deviceCapabilityHandler = deviceCapabilityHandler,
    )

    @Test
    fun `revoking a device capability goes through its handler`() = runBlocking<Unit> {
        interactor.togglePermission(productId, ProductPermissionStatus(alarm, granted = true))

        verify(deviceCapabilityHandler).revoke(productId, alarm)
        verifyNoInteractions(permissionRepository)
    }

    @Test
    fun `revoking another permission goes straight to the repository`() = runBlocking<Unit> {
        interactor.togglePermission(productId, ProductPermissionStatus(ProductPermission.BalanceAccess, granted = true))

        verify(permissionRepository).revoke(productId, ProductPermission.BalanceAccess)
        verifyNoInteractions(deviceCapabilityHandler)
    }

    @Test
    fun `granting a device capability stores the grant`() = runBlocking<Unit> {
        interactor.togglePermission(productId, ProductPermissionStatus(alarm, granted = false))

        verify(permissionRepository).grant(productId, alarm)
        verifyNoInteractions(deviceCapabilityHandler)
    }
}
