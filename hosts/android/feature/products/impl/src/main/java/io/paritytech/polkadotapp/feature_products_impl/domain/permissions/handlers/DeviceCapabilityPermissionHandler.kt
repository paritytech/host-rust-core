package io.paritytech.polkadotapp.feature_products_impl.domain.permissions.handlers

import android.Manifest
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.net.toUri
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import io.paritytech.polkadotapp.common.presentation.resources.ContextManager
import io.paritytech.polkadotapp.common.utils.canScheduleExactAlarms
import io.paritytech.polkadotapp.common.utils.logFailure
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
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.util.UUID
import javax.inject.Inject
import kotlin.coroutines.resume

private const val KEY_EXACT_ALARM_ASKED = "product_exact_alarm_access_asked"

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
        if (capability == DeviceCapabilityType.Alarm) requestExactAlarmIfNeeded()
        return true
    }

    // Asked once per install. A refusal is not a deny: the alarm falls back to an inexact one.
    private suspend fun requestExactAlarmIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        if (preferences.getBoolean(KEY_EXACT_ALARM_ASKED, false)) return
        runCancellableCatching {
            val activity = contextManager.requireActivity()
            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, "package:${activity.packageName}".toUri())
            var launcher: ActivityResultLauncher<Intent>? = null
            var observer: LifecycleEventObserver? = null
            // Main thread: lifecycle observers must be added and removed there.
            withContext(Dispatchers.Main.immediate) {
                if (activity.canScheduleExactAlarms()) return@withContext
                // A destroyed activity never delivers ON_DESTROY again, so the wait below would not end.
                if (activity.lifecycle.currentState == Lifecycle.State.DESTROYED) return@withContext
                preferences.putBoolean(KEY_EXACT_ALARM_ASKED, true)
                try {
                    suspendCancellableCoroutine { continuation ->
                        val resume = { if (continuation.isActive) continuation.resume(Unit) }
                        // A destroyed activity drops the result callback, so stop waiting then.
                        observer = LifecycleEventObserver { _, event ->
                            if (event == Lifecycle.Event.ON_DESTROY) resume()
                        }.also(activity.lifecycle::addObserver)
                        activity.activityResultRegistry.register(
                            UUID.randomUUID().toString(),
                            ActivityResultContracts.StartActivityForResult(),
                        ) { resume() }.also { launcher = it }.launch(intent)
                    }
                } finally {
                    launcher?.unregister()
                    observer?.let(activity.lifecycle::removeObserver)
                }
            }
        }.logFailure("exact alarm access request")
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
