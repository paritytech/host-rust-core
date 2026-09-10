package io.paritytech.polkadotapp.common.presentation.notifications.permissionAsker.compose

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import dagger.hilt.android.EntryPointAccessors
import io.paritytech.polkadotapp.common.di.modules.PermissionAskerEntryPoint
import io.paritytech.polkadotapp.common.utils.permissions.PermissionAsker

@Composable
fun rememberPermissionAsker(): PermissionAsker {
    val context = LocalContext.current

    return remember(context) {
        EntryPointAccessors.fromApplication(
            context.applicationContext,
            PermissionAskerEntryPoint::class.java
        ).permissionAsker()
    }
}
