@file:OptIn(kotlin.time.ExperimentalTime::class)

package io.paritytech.polkadotapp.feature_people_impl.data.personSetup

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.hilt.work.HiltWorker
import androidx.work.*
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.common.data.worker.stateMachine.ExecutionOutcome
import io.paritytech.polkadotapp.common.data.worker.stateMachine.executeUntilPossible
import io.paritytech.polkadotapp.common.data.worker.stateMachine.toWorkerResult
import io.paritytech.polkadotapp.common.utils.FeatureFlags
import io.paritytech.polkadotapp.common.utils.FeatureOption
import timber.log.Timber
import java.util.concurrent.TimeUnit
import kotlin.time.Clock
import kotlin.time.Instant

@HiltWorker
class PersonSetupWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted parameters: WorkerParameters,
    private val personSetupDataSourceFactory: PersonSetupDataSource.Factory,
    private val personSetupStateMachineFactory: PersonSetupStateMachineFactory
) : CoroutineWorker(appContext, parameters) {
    companion object {
        private const val WORK_ID = "PersonSetup"
        private const val TAG = "PersonSetupWorker"

        private val NOTIFICATION_ID = WORK_ID.hashCode()

        fun startPersonSetup(context: Context) {
            val uploadWorkRequest = OneTimeWorkRequestBuilder<PersonSetupWorker>()
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .setBackoffCriteria()
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .build()
                )
                .build()

            WorkManager.getInstance(context)
                .enqueueUniqueWork(WORK_ID, ExistingWorkPolicy.KEEP, uploadWorkRequest)
        }

        private fun OneTimeWorkRequest.Builder.setBackoffCriteria(): OneTimeWorkRequest.Builder {
            if (FeatureFlags.isEnabled(FeatureOption.SHORT_WORKER_BACKOFF)) {
                setBackoffCriteria(BackoffPolicy.LINEAR, backoffDelay = 10, timeUnit = TimeUnit.SECONDS)
            } else {
                setBackoffCriteria(BackoffPolicy.EXPONENTIAL, backoffDelay = 30, timeUnit = TimeUnit.SECONDS)
            }

            return this
        }
    }

    private val notificationManager = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    override suspend fun doWork(): Result {
        Timber.tag(TAG).d("doWork start")
        return personSetupDataSourceFactory.withDataSource { dataSource ->
            val stateMachine = personSetupStateMachineFactory.create(dataSource)

            when (val outcome = stateMachine.executeUntilPossible()) {
                is ExecutionOutcome.WaitUntil -> {
                    rescheduleAt(outcome.epoch)
                    Timber.tag(TAG).d("doWork end (rescheduled at epoch=${outcome.epoch})")
                    Result.success()
                }

                ExecutionOutcome.Done,
                is ExecutionOutcome.Failure -> {
                    Timber.tag(TAG).d("doWork end outcome=$outcome")
                    outcome.toWorkerResult(retryOnFailure = true)
                }
            }
        }
    }

    /**
     * Re-enqueues the polling worker with a precise initial delay derived from [epoch]. Replaces
     * exception-based wait signalling — the state machine produced a [ExecutionOutcome.WaitUntil]
     * and the worker honours it without throwing.
     */
    private fun rescheduleAt(epoch: Instant) {
        val delayMs = (epoch - Clock.System.now()).inWholeMilliseconds.coerceAtLeast(0L)
        val request = OneTimeWorkRequestBuilder<PersonSetupWorker>()
            .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
            .setBackoffCriteria()
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .build()

        WorkManager.getInstance(applicationContext)
            .enqueueUniqueWork(WORK_ID, ExistingWorkPolicy.REPLACE, request)
    }

    override suspend fun getForegroundInfo(): ForegroundInfo {
        val title = applicationContext.getString(R.string.people_ring_setup_notification_title)
        val message = applicationContext.getString(R.string.people_ring_setup_notification_message)

        val channelId = createChannel()

        val notification = NotificationCompat.Builder(applicationContext, channelId)
            .setContentTitle(title)
            .setSmallIcon(R.drawable.ic_upgrade)
            .setTicker(title)
            .setContentText(message)
            .setOngoing(true)
            .build()

        return ForegroundInfo(NOTIFICATION_ID, notification)
    }

    private fun createChannel(): String {
        val channelId = applicationContext.getString(R.string.workers_notification_channel_id)

        val channel = NotificationChannel(
            channelId,
            applicationContext.getString(R.string.workers_notification_channel_name),
            NotificationManager.IMPORTANCE_LOW
        )

        notificationManager.createNotificationChannel(channel)

        return channelId
    }
}
