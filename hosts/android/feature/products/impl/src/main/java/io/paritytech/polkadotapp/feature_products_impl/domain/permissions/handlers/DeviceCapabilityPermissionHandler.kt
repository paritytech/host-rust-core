package io.paritytech.polkadotapp.feature_products_impl.domain.permissions.handlers

import android.Manifest
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResult
import androidx.core.app.NotificationManagerCompat
import androidx.core.net.toUri
import androidx.lifecycle.Lifecycle
import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import io.paritytech.polkadotapp.common.presentation.resources.ContextManager
import io.paritytech.polkadotapp.common.utils.ActivityResultExecutor
import io.paritytech.polkadotapp.common.utils.canScheduleExactAlarms
import io.paritytech.polkadotapp.common.utils.permissions.PermissionAsker
import io.paritytech.polkadotapp.common.utils.permissions.PermissionResult
import io.paritytech.polkadotapp.common.utils.runCancellableCatching
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.ProductPermissionRepository
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.ProductPermissionRequester
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.models.DeviceCapabilityType
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.models.PermissionDecision
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.models.ProductPermission
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.withContext
import javax.inject.Inject

private const val KEY_EXACT_ALARM_REFUSED = "product_exact_alarm_access_refused"

/** What the OS says about ringing an alarm, which needs notifications and an exact alarm. */
enum class AlarmAccess { Allowed, Refused, Unasked }

class DeviceCapabilityPermissionHandler @Inject constructor(
    private val repository: ProductPermissionRepository,
    private val requester: ProductPermissionRequester,
    private val permissionAsker: PermissionAsker,
    private val contextManager: ContextManager,
    private val preferences: Preferences,
) : ProductPermissionHandler<ProductPermission.DeviceCapability> {
    override suspend fun isGranted(productId: ProductId, permission: ProductPermission.DeviceCapability): Boolean {
        return repository.isGranted(productId, permission)
    }

    override suspend fun request(productId: ProductId, permission: ProductPermission.DeviceCapability): Boolean {
        if (isGranted(productId, permission)) {
            return requestOsPermissionIfNeeded(permission.capability)
        }

        val decision = requester.prompt(productId, permission)
        if (decision == PermissionDecision.Deny) return false

        val osGranted = requestOsPermissionIfNeeded(permission.capability)
        if (!osGranted) return false

        when (decision) {
            PermissionDecision.AllowAlways -> repository.grant(productId, permission)
            PermissionDecision.AllowOnce -> repository.grantOneTime(productId, permission)
            else -> Unit
        }
        return true
    }

    override suspend fun revoke(productId: ProductId, permission: ProductPermission.DeviceCapability) {
        repository.revoke(productId, permission)
    }

    suspend fun requestOsPermissionIfNeeded(capability: DeviceCapabilityType): Boolean {
        val manifestPermissions = capability.toManifestPermissions()
        if (manifestPermissions.isNotEmpty() &&
            permissionAsker.askPermission(*manifestPermissions.toTypedArray()) != PermissionResult.GRANTED
        ) {
            return false
        }
        // An alarm rings on time only as an exact alarm; refused, the core falls back to a notification.
        return capability != DeviceCapabilityType.Alarm || requestExactAlarms()
    }

    // Refused, the answer is reported as OS-denied until the user allows it in system settings, so the
    // core falls back to a notification without asking again.
    fun alarmAccess(): AlarmAccess {
        val context = contextManager.applicationContext
        return when {
            !NotificationManagerCompat.from(context).areNotificationsEnabled() -> when {
                Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU -> AlarmAccess.Refused
                notificationsDeniedForever() -> AlarmAccess.Refused
                else -> AlarmAccess.Unasked
            }
            context.canScheduleExactAlarms() -> AlarmAccess.Allowed
            preferences.getBoolean(KEY_EXACT_ALARM_REFUSED, false) -> AlarmAccess.Refused
            else -> AlarmAccess.Unasked
        }
    }

    private fun notificationsDeniedForever() = runCatching {
        permissionAsker.getPermissionState(Manifest.permission.POST_NOTIFICATIONS) == PermissionResult.DENIED_FOREVER
    }.getOrDefault(false)

    private suspend fun requestExactAlarms(): Boolean {
        if (contextManager.applicationContext.canScheduleExactAlarms()) return true
        val allowed = withContext(Dispatchers.Main.immediate) {
            runCancellableCatching { askExactAlarms(contextManager.requireActivity()) }.getOrNull()
        } ?: return false
        preferences.putBoolean(KEY_EXACT_ALARM_REFUSED, !allowed)
        return allowed
    }

    // A destroyed activity drops the settings result, so the wait ends with it, unanswered.
    private suspend fun askExactAlarms(activity: ComponentActivity): Boolean? = coroutineScope {
        val answer = async { ExactAlarmAccessExecutor(activity).execute().getOrNull() }
        val destroyed = launch { activity.lifecycle.currentStateFlow.first { it == Lifecycle.State.DESTROYED } }
        select<Boolean?> {
            answer.onAwait { it }
            destroyed.onJoin { null }
        }.also { coroutineContext.cancelChildren() }
    }

    private fun DeviceCapabilityType.toManifestPermissions(): List<String> = when (this) {
        DeviceCapabilityType.Camera -> listOf(Manifest.permission.CAMERA)
        DeviceCapabilityType.Microphone -> listOf(Manifest.permission.RECORD_AUDIO)
        DeviceCapabilityType.Bluetooth -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            listOf(Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            emptyList()
        }
        DeviceCapabilityType.Location -> listOf(Manifest.permission.ACCESS_FINE_LOCATION)
        DeviceCapabilityType.Notifications,
        DeviceCapabilityType.Alarm -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            listOf(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            emptyList()
        }
        DeviceCapabilityType.NFC -> listOf(Manifest.permission.NFC)
        // READ as well: deduping an added event queries the calendar.
        DeviceCapabilityType.Calendar -> listOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR)
        DeviceCapabilityType.Clipboard,
        DeviceCapabilityType.Biometrics,
        DeviceCapabilityType.OpenUrl -> emptyList()
    }
}

// The settings screen returns CANCELED whatever the user chose, so the answer is read back from the OS.
private class ExactAlarmAccessExecutor(
    private val activity: ComponentActivity,
) : ActivityResultExecutor<Boolean>(activity) {
    override fun createIntent() =
        Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, "package:${activity.packageName}".toUri())

    override fun handleResult(result: ActivityResult) = Result.success(activity.canScheduleExactAlarms())
}
