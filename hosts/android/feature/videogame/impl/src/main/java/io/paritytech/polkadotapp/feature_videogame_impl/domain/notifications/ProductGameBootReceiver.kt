package io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import io.paritytech.polkadotapp.common.utils.launchAsyncJob
import io.paritytech.polkadotapp.common.utils.logFailure

class ProductGameBootReceiver : BroadcastReceiver() {
    @EntryPoint
    @InstallIn(SingletonComponent::class)
    interface Dependencies {
        fun productGameReminder(): RealProductGameReminder
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        // Resolved lazily rather than via @AndroidEntryPoint: the generated injection runs before the
        // action check and blows up when the broadcast reaches a process whose graph is not built yet
        // (HiltTestApplication under instrumentation). Restoring the reminder is best-effort — skip instead.
        val productGameReminder = runCatching {
            EntryPointAccessors.fromApplication(context.applicationContext, Dependencies::class.java).productGameReminder()
        }.getOrNull() ?: return

        launchAsyncJob {
            runCatching { productGameReminder.restore() }.logFailure("product game reminder restore")
        }
    }
}
