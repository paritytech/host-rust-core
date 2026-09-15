package io.paritytech.polkadotapp.feature_people_impl.data.notifications

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

interface BecomeCitizenNotificationPublisher {
    fun publishBecomeCitizen()
}

class RealBecomeCitizenNotificationPublisher @Inject constructor(
    @ApplicationContext context: Context,
    intentProvider: ActivityIntentProvider,
    private val chatDeeplinkMapper: ChatDeeplinkMapper,
) : NotificationPublisher(context, intentProvider), BecomeCitizenNotificationPublisher {
    private companion object {
        const val CITIZEN_NOTIFICATION_ID = 2033
    }

    override fun publishBecomeCitizen() {
        val channel = PolkadotNotificationChannel.BECOME_CITIZEN

        val notification = NotificationCompat.Builder(appContext, channel.id)
            .setupDefaultNotification(deepLink = createDeeplink())
            .setContentTitle(appContext.getString(RCommon.string.chat_bot_notification_citizenship_issued_title))
            .setContentText(appContext.getString(RCommon.string.chat_bot_notification_citizenship_issued_description))
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .build()

        publish(CITIZEN_NOTIFICATION_ID, channel, notification)
    }

    private fun createDeeplink() = chatDeeplinkMapper.toDeeplink(chatId = ChatBotData.weeklyGame().chatId)
}
