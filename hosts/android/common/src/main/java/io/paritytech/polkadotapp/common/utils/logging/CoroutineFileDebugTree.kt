package io.paritytech.polkadotapp.common.utils.logging

import android.annotation.SuppressLint
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.io.File
import java.io.FileWriter
import java.io.IOException
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

/**
 * This is a basic implementation of a Timber.DebugTree that saves logs to a file using the provided coroutineScope
 * @param coroutineScope should be managed by the consumer
 */
@SuppressLint("LogNotTimber")
abstract class CoroutineFileDebugTree(
    coroutineScope: CoroutineScope,
    private val fallbackLogTag: String,
    private val logFile: File
) : Timber.DebugTree() {
    companion object {
        private val LOG_TIMESTAMP_FORMAT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS")
    }

    private val logChannel = Channel<String>(Channel.UNLIMITED)

    private var logWriter: FileWriter? = null

    init {
        coroutineScope.launch {
            try {
                logWriter = FileWriter(logFile, true)
                listenForLogs()
            } catch (e: IOException) {
                Log.e("CoroutineFileDebugTree", "Cannot open log file for writing. Logger is disabled", e)
            }
        }
    }

    override fun log(priority: Int, tag: String?, message: String, t: Throwable?) {
        val finalTag = tag ?: fallbackLogTag

        var fullMessage = "$finalTag ${priorityToString(priority)} $message"

        if (t != null) {
            fullMessage += "\n${Log.getStackTraceString(t)}"
        }

        logChannel.trySend(fullMessage)
    }

    private suspend fun listenForLogs() {
        try {
            for (message in logChannel) {
                try {
                    val logTimestamp = LOG_TIMESTAMP_FORMAT.format(ZonedDateTime.now(ZoneOffset.UTC))
                    logWriter?.append("$logTimestamp $message\n")
                    logWriter?.flush()
                } catch (e: IOException) {
                    Log.e("CoroutineFileDebugTree", "Failed to write to log file", e)
                }
            }
        } finally {
            withContext(NonCancellable) {
                try {
                    logWriter?.close()
                    logWriter = null
                    Log.d("CoroutineFileDebugTree", "File logger stopped and file closed")
                } catch (e: IOException) {
                    Log.e("CoroutineFileDebugTree", "Failed to close log writer", e)
                }
            }
        }
    }

    private fun priorityToString(priority: Int): String = when (priority) {
        Log.VERBOSE -> "VERBOSE"
        Log.DEBUG -> "DEBUG"
        Log.INFO -> "INFO"
        Log.WARN -> "WARN"
        Log.ERROR -> "ERROR"
        Log.ASSERT -> "ASSERT"
        else -> "?"
    }
}
