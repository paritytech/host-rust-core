package io.paritytech.polkadotapp.feature_become_citizen_impl.data.notifications

import android.content.Context
import androidx.core.app.NotificationCompat
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.common.presentation.ActivityIntentProvider
import io.paritytech.polkadotapp.common.presentation.notifications.NotificationPublisher
import io.paritytech.polkadotapp.common.presentation.notifications.PolkadotNotificationChannel
import io.paritytech.polkadotapp.feature_chats_api.deeplink.ChatDeeplinkMapper
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotData
import javax.inject.Inject
import io.paritytech.polkadotapp.common.R as RCommon

interface EvidenceNotificationsPublisher {
    fun publishPhotoAccepted()

    fun publishVideoAccepted()
}

class RealEvidenceNotificationsPublisher @Inject constructor(
    @ApplicationContext context: Context,
    intentProvider: ActivityIntentProvider,
    private val chatDeeplinkMapper: ChatDeeplinkMapper
) : NotificationPublisher(context, intentProvider), EvidenceNotificationsPublisher {
    private companion object {
        const val PHOTO_NOTIFICATION_ID = 2032
        const val VIDEO_NOTIFICATION_ID = 2033
    }

    override fun publishPhotoAccepted() {
        val channel = PolkadotNotificationChannel.TATTOO_BOT

        val notification = NotificationCompat.Builder(appContext, channel.id)
            .setupDefaultNotification(deepLink = createDeeplink())
            .setContentTitle(appContext.getString(RCommon.string.chat_bot_tattoo_notification_photo_title))
            .setContentText(appContext.getString(RCommon.string.chat_bot_tattoo_notification_photo_description))
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()

        publish(PHOTO_NOTIFICATION_ID, channel, notification)
    }

    override fun publishVideoAccepted() {
        val channel = PolkadotNotificationChannel.TATTOO_BOT

        val notification = NotificationCompat.Builder(appContext, channel.id)
            .setupDefaultNotification(deepLink = createDeeplink())
            .setContentTitle(appContext.getString(RCommon.string.chat_bot_tattoo_notification_video_title))
            .setContentText(appContext.getString(RCommon.string.chat_bot_tattoo_notification_video_description))
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()

        publish(VIDEO_NOTIFICATION_ID, channel, notification)
    }

    private fun createDeeplink() = chatDeeplinkMapper.toDeeplink(chatId = ChatBotData.tattoo().chatId)
}
