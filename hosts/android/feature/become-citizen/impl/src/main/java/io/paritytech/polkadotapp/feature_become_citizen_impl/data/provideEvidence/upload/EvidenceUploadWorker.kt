package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.hilt.work.HiltWorker
import androidx.work.*
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.common.data.worker.stateMachine.executeUntilPossible
import io.paritytech.polkadotapp.common.data.worker.stateMachine.toWorkerResult
import io.paritytech.polkadotapp.common.utils.FeatureFlags
import io.paritytech.polkadotapp.common.utils.FeatureOption
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceStateMachineFactory
import java.util.concurrent.TimeUnit

@HiltWorker
class EvidenceUploadWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted parameters: WorkerParameters,
    private val evidenceUploader: EvidenceUploader,
    private val evidenceStateMachineFactory: UploadEvidenceStateMachineFactory
) : CoroutineWorker(appContext, parameters) {
    companion object {
        private const val WORK_ID = "EvidenceUpload"
        private val NOTIFICATION_ID = WORK_ID.hashCode()

        fun startEvidenceUpload(context: Context) {
            val uploadWorkRequest = OneTimeWorkRequestBuilder<EvidenceUploadWorker>()
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .setBackoffCriteria()
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .build()
                )
                .build()

            WorkManager.getInstance(context)
                .enqueueUniqueWork(WORK_ID, ExistingWorkPolicy.REPLACE, uploadWorkRequest)
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
        return evidenceUploader.withUploadingSession {
            val stateMachine = evidenceStateMachineFactory.create(it)

            stateMachine
                .executeUntilPossible()
                .toWorkerResult(retryOnFailure = true)
        }
    }

    override suspend fun getForegroundInfo(): ForegroundInfo {
        val title = applicationContext.getString(R.string.become_citizen_provide_evidence_notification_title)
        val message = applicationContext.getString(R.string.become_citizen_provide_evidence_notification_message)

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
