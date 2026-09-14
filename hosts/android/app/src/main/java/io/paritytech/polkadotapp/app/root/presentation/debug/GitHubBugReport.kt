package io.paritytech.polkadotapp.app.root.presentation.debug

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.app.BuildConfig
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.common.utils.mapError
import io.paritytech.polkadotapp.common.utils.runCancellableCatching
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File
import javax.inject.Inject
import io.paritytech.polkadotapp.common.R as RCommon

class GitHubBugReport @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val dispatchers: CoroutineDispatchers,
) {
    suspend fun report(archive: File): Result<Unit> =
        saveLogs(archive).flatMap(::openIssue)

    private suspend fun saveLogs(archive: File): Result<String> {
        return try {
            withContext(dispatchers.io) {
                runCancellableCatching {
                    val resolver = context.contentResolver
                    val values = ContentValues().apply {
                        put(MediaStore.Downloads.DISPLAY_NAME, archive.name)
                        put(MediaStore.Downloads.MIME_TYPE, "application/zip")
                        put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                        put(MediaStore.Downloads.IS_PENDING, 1)
                    }
                    val uri = requireNotNull(resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values))
                    try {
                        archive.inputStream().use { input ->
                            requireNotNull(resolver.openOutputStream(uri)).use { output ->
                                input.copyTo(output)
                            }
                        }
                        ensureActive()
                        val ready = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
                        check(resolver.update(uri, ready, null, null) == 1)
                        archive.name
                    } catch (error: Throwable) {
                        runCatching { resolver.delete(uri, null, null) }
                            .logFailure("Remove incomplete bug report")
                        throw error
                    }
                }.mapError(BugReportError::SaveLogs)
            }
        } finally {
            withContext(NonCancellable + dispatchers.io) {
                archive.delete()
            }
        }
    }

    private fun openIssue(fileName: String): Result<Unit> = runCancellableCatching {
        val details = context.getString(
            RCommon.string.debug_report_bug_details,
            BuildConfig.VERSION_NAME,
            BuildConfig.VERSION_CODE,
            BuildConfig.BUILD_TYPE,
            BuildConfig.FLAVOR,
            Build.VERSION.RELEASE,
            Build.VERSION.SDK_INT,
            Build.MANUFACTURER,
            Build.MODEL,
            fileName,
        )
        val uri = Uri.parse("https://github.com/paritytech/platform-issues/issues/new").buildUpon()
            .appendQueryParameter("template", "bug_report.yml")
            .appendQueryParameter("title", context.getString(RCommon.string.debug_report_bug_title))
            .appendQueryParameter("where", context.getString(RCommon.string.debug_report_bug_product))
            .appendQueryParameter("details", details)
            .build()
        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            selector = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_APP_BROWSER)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }.mapError(BugReportError::OpenBrowser)
}
