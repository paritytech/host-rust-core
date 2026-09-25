package io.paritytech.polkadotapp.feature_products_impl.domain.permissions.handlers

import io.paritytech.polkadotapp.common.utils.permissions.PermissionAsker
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders.GameReminderCenter
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.ProductPermissionRepository
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.ProductPermissionRequester
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.models.DeviceCapabilityType
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.models.ProductPermission
import io.paritytech.polkadotapp.test_shared.any
import kotlinx.coroutines.runBlocking
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.verify

class DeviceCapabilityPermissionHandlerTest {
    private val repository: ProductPermissionRepository = mock()
    private val gameReminderCenter: GameReminderCenter = mock()

    private val productId = ProductId.fromStoredValue("jollity.dot")

    private val handler = DeviceCapabilityPermissionHandler(
        repository = repository,
        requester = mock(ProductPermissionRequester::class.java),
        permissionAsker = mock(PermissionAsker::class.java),
        gameReminderCenter = gameReminderCenter,
    )

    @Test
    fun `revoking the alarm capability cancels the product's game reminder`() = runBlocking<Unit> {
        val alarm = ProductPermission.DeviceCapability(DeviceCapabilityType.Alarm)

        handler.revoke(productId, alarm)

        verify(repository).revoke(productId, alarm)
        verify(gameReminderCenter).cancel(productId.value)
    }

    @Test
    fun `revoking another capability keeps the game reminder`() = runBlocking<Unit> {
        val notifications = ProductPermission.DeviceCapability(DeviceCapabilityType.Notifications)

        handler.revoke(productId, notifications)

        verify(repository).revoke(productId, notifications)
        verify(gameReminderCenter, never()).cancel(any())
    }
}
