package io.paritytech.polkadotapp.app.root.data.debug

import io.paritytech.polkadotapp.app.root.domain.debug.IssueReport
import io.paritytech.polkadotapp.app.root.domain.debug.IssueReportApi
import io.paritytech.polkadotapp.app.root.domain.debug.IssueReportSubmissionError
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.common.utils.InformationSize.Companion.bytes
import io.paritytech.polkadotapp.common.utils.InformationSize.Companion.megabytes
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.runCancellableCatching
import io.paritytech.polkadotapp.tools_remoteconfig_api.RemoteConfigService
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.Response
import okio.BufferedSink
import java.io.IOException
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class RealIssueReportApi @Inject constructor(
    private val remoteConfig: RemoteConfigService,
    builder: OkHttpClient.Builder,
    private val dispatchers: CoroutineDispatchers,
) : IssueReportApi {
    private val client = builder
        .apply {
            interceptors().clear()
            networkInterceptors().clear()
        }
        .cache(null)
        .retryOnConnectionFailure(false)
        .followRedirects(false)
        .followSslRedirects(false)
        .connectTimeout(20, TimeUnit.SECONDS)
        .writeTimeout(5, TimeUnit.MINUTES)
        .readTimeout(5, TimeUnit.MINUTES)
        .callTimeout(5, TimeUnit.MINUTES)
        .build()

    override suspend fun send(report: IssueReport): Result<Unit> = withContext(dispatchers.io) {
        remoteConfig.getString("issue_proxy_url").flatMap { endpoint ->
            remoteConfig.getString("issue_proxy_api_key").flatMap { configuredKey ->
                val url = endpoint.trim().toHttpUrlOrNull()
                val key = configuredKey.trim()
                if (url == null || !url.isHttps || url.username.isNotEmpty() || url.password.isNotEmpty() ||
                    url.fragment != null || key.isEmpty() || key.any { it.code !in 33..126 }
                ) {
                    Result.failure(IssueReportSubmissionError.NotConfigured)
                } else {
                    runCancellableCatching {
                        val body = MultipartBody.Builder().setType(MultipartBody.FORM)
                            .addFormDataPart("title", "Android app issue")
                            .addFormDataPart("body", report.description)
                            .addFormDataPart("screenshot", "screenshot.png", report.screenshot.asRequestBody("image/png".toMediaType()))
                            .addFormDataPart("logs", "logs.zip", report.logs.asRequestBody("application/zip".toMediaType()))
                            .build()
                        if (report.screenshot.length().bytes > 10.megabytes || body.contentLength().bytes > 25.megabytes) {
                            Result.failure(IssueReportSubmissionError.AttachmentsTooLarge)
                        } else {
                            val request = Request.Builder()
                                .url(url)
                                .header("Authorization", "Bearer $key")
                                .post(object : RequestBody() {
                                    override fun contentType() = body.contentType()
                                    override fun contentLength() = body.contentLength()
                                    override fun writeTo(sink: BufferedSink) = body.writeTo(sink)
                                    override fun isOneShot() = true
                                })
                                .build()
                            submit(request)
                            Result.success(Unit)
                        }
                    }.flatMap { it }
                }
            }
        }
    }

    private suspend fun submit(request: Request): Unit = suspendCancellableCoroutine { continuation ->
        val call = client.newCall(request)
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, exception: IOException) {
                if (continuation.isActive) continuation.resumeWithException(exception)
            }

            override fun onResponse(call: Call, response: Response) {
                response.use {
                    if (continuation.isActive) {
                        if (response.code == 201) continuation.resume(Unit)
                        else continuation.resumeWithException(IssueReportSubmissionError.HttpFailure(response.code))
                    }
                }
            }
        })
    }
}
