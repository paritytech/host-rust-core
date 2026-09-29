package io.paritytech.polkadotapp.feature_videogame_impl.data.voucher

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.chains.multiNetwork.connection.ChainConnectionRefCounter
import io.paritytech.polkadotapp.chains.multiNetwork.connection.withConnectionEnabled
import io.paritytech.polkadotapp.common.utils.FeatureFlags
import io.paritytech.polkadotapp.common.utils.FeatureOption
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.common.utils.toWorkerResult
import timber.log.Timber
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import kotlin.time.Duration.Companion.days
import kotlin.time.Duration.Companion.minutes
import io.paritytech.polkadotapp.common.R as RCommon
import kotlin.Result as KResult

class RegisterScoreVouchersWorker(
    private val appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {
    interface SyncExecutor {
        suspend fun executeSync(): KResult<Unit>
    }

    @Inject
    lateinit var chainConnectionRefCounter: ChainConnectionRefCounter

    @Inject
    lateinit var knownChains: KnownChains

    @Inject
    lateinit var executor: RegisterScoreVouchersExecutor

    companion object {
        private const val WORK_ID = "ScoreRewardsSync"

        private val NOTIFICATION_ID = WORK_ID.hashCode()

        fun startRegisterScoreVouchersWorker(context: Context) {
            val request = PeriodicWorkRequestBuilder<RegisterScoreVouchersWorker>(
                repeatInterval = getRepeatIntervalMillis(),
                repeatIntervalTimeUnit = TimeUnit.MILLISECONDS
            ).setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            ).build()

            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(WORK_ID, ExistingPeriodicWorkPolicy.CANCEL_AND_REENQUEUE, request)
        }

        private fun getRepeatIntervalMillis(): Long {
            // TODO v1: setup a proper production interval (at most half of the claiming interval)
            val duration = if (FeatureFlags.isEnabled(FeatureOption.SHORT_WORKER_BACKOFF)) 15.minutes else 1.days
            return duration.inWholeMilliseconds
        }
    }

    override suspend fun doWork(): Result {
        return chainConnectionRefCounter.withConnectionEnabled(knownChains.people, "RegisterScoreVouchersWorker") {
            performSync()
        }.toWorkerResult()
    }

    private suspend fun performSync(): kotlin.Result<Unit> {
        // We attempt to invoke all executors but return failure if at least one has failed
        return executorList().fold(KResult.success(Unit)) { acc, syncExecutor ->
            val executorLabel = syncExecutor::class.simpleName

            Timber.d("Starting syncing with $executorLabel")

            val nextResult = syncExecutor.executeSync()
                .logFailure("Syncing with $executorLabel failed")
                .onSuccess { Timber.d("Syncing with $executorLabel succeeded") }

            acc.flatMap { nextResult }
        }
    }

    private fun executorList(): List<SyncExecutor> {
        return listOf(executor)
    }

    override suspend fun getForegroundInfo(): ForegroundInfo {
        val title = applicationContext.getString(RCommon.string.mobrule_rewards_sync_worker_notification_title)
        val message = applicationContext.getString(RCommon.string.mobrule_rewards_sync_worker_notification_message)

        val channelId = createChannel()

        val notification = NotificationCompat.Builder(applicationContext, channelId)
            .setContentTitle(title)
            .setSmallIcon(RCommon.drawable.ic_upgrade)
            .setTicker(title)
            .setContentText(message)
            .setOngoing(true)
            .build()

        return ForegroundInfo(NOTIFICATION_ID, notification)
    }

    private fun createChannel(): String {
        val channelId = applicationContext.getString(RCommon.string.workers_notification_channel_id)

        val channel = NotificationChannel(
            channelId,
            applicationContext.getString(RCommon.string.workers_notification_channel_name),
            NotificationManager.IMPORTANCE_LOW
        )
        val notificationManager = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.createNotificationChannel(channel)

        return channelId
    }
}
