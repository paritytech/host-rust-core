package io.paritytech.polkadotapp.app.root.presentation.debug

import android.content.ContentUris
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.paritytech.polkadotapp.common.utils.RealCoroutineDispatchers
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

@RunWith(AndroidJUnit4::class)
class GitHubBugReportTest {
    private val appContext = InstrumentationRegistry.getInstrumentation().targetContext
    private val context = BrowserContext(appContext)
    private val reporter = GitHubBugReport(context, RealCoroutineDispatchers())
    private lateinit var archive: File

    @Before
    fun setUp() {
        archive = File.createTempFile("bug-report-test-", ".zip", appContext.cacheDir)
        ZipOutputStream(archive.outputStream()).use { output ->
            output.putNextEntry(ZipEntry("app_logs.log"))
            output.write("A reproducible test failure\n".toByteArray())
            output.closeEntry()
        }
    }

    @After
    fun tearDown() {
        archive.delete()
        downloads().forEach { appContext.contentResolver.delete(it, null, null) }
    }

    @Test
    fun savesLogsAndOpensGitHubReport() = runBlocking<Unit> {
        val expected = archive.readBytes()

        reporter.report(archive).getOrThrow()

        val download = downloads().single()
        val actual = appContext.contentResolver.openInputStream(download)!!.use { it.readBytes() }
        assertArrayEquals(expected, actual)
        appContext.contentResolver.query(
            download,
            arrayOf(MediaStore.Downloads.DISPLAY_NAME, MediaStore.Downloads.MIME_TYPE, MediaStore.Downloads.IS_PENDING),
            null,
            null,
            null,
        )!!.use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals(listOf(archive.name, "application/zip", "0"), (0..2).map(cursor::getString))
        }
        assertFalse(archive.exists())

        val intent = context.opened.single()
        val uri = intent.data!!
        assertEquals(
            listOf(Intent.ACTION_VIEW, Intent.ACTION_MAIN, Intent.CATEGORY_APP_BROWSER),
            listOf(intent.action, intent.selector!!.action, intent.selector!!.categories.single()),
        )
        assertEquals(
            listOf("https", "github.com", "/paritytech/platform-issues/issues/new", "bug_report.yml", "Polkadot Mobile (Android)"),
            listOf(uri.scheme, uri.host, uri.path, uri.getQueryParameter("template"), uri.getQueryParameter("where")),
        )
        val details = uri.getQueryParameter("details")!!
        assertTrue(details.contains(archive.name))
        assertFalse(details.contains("A reproducible test failure"))
        assertEquals(Intent.FLAG_ACTIVITY_NEW_TASK, intent.flags)
    }

    private fun downloads(): List<Uri> {
        return appContext.contentResolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.Downloads._ID),
            "${MediaStore.Downloads.DISPLAY_NAME} = ?",
            arrayOf(archive.name),
            null,
        )!!.use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    add(ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, cursor.getLong(0)))
                }
            }
        }
    }

    private class BrowserContext(context: Context) : ContextWrapper(context) {
        val opened = mutableListOf<Intent>()

        override fun startActivity(intent: Intent) {
            opened += intent
        }
    }
}
