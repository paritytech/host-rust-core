package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.record

import android.content.Context
import androidx.camera.core.SurfaceRequest
import androidx.camera.video.*
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.common.utils.Fraction
import io.paritytech.polkadotapp.common.utils.Fraction.Companion.percents
import io.paritytech.polkadotapp.common.utils.InformationSize
import io.paritytech.polkadotapp.common.utils.camera.CameraBinder
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.suspendCancellableCoroutine
import java.io.File
import javax.inject.Inject
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.time.Duration
import kotlin.time.Duration.Companion.nanoseconds

class VideoFileRecorder @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val cameraBinder: CameraBinder
) {
    private val mutableState = MutableStateFlow(State())
    val state = mutableState.asStateFlow()

    private var activeRecording: Recording? = null

    private val recorder = Recorder.Builder()
        .setQualitySelector(QualitySelector.from(Quality.HD))
        .setTargetVideoEncodingBitRate(2500)
        .build()

    private val videoCapture = VideoCapture.withOutput(recorder)

    suspend fun bind(
        lifecycleOwner: LifecycleOwner,
        surfaceRequest: (SurfaceRequest) -> Unit
    ) {
        cameraBinder.bind(lifecycleOwner, surfaceRequest, videoCapture)
    }

    suspend fun record(
        outputFile: File,
        maxDuration: Duration = Duration.ZERO,
        maxFileSize: InformationSize = InformationSize.ZERO
    ): Result<Unit> = runCatching {
        if (activeRecording != null) error("Already in recording state")

        suspendCancellableCoroutine { continuation ->
            mutableState.update { it.copy(isRecording = true) }

            val outputOptions = FileOutputOptions
                .Builder(outputFile)
                .apply {
                    setDurationLimitMillis(maxDuration.inWholeMilliseconds)
                    setFileSizeLimit(maxFileSize.inWholeBytes)
                }
                .build()

            activeRecording = videoCapture.output.prepareRecording(context, outputOptions)
                .start(ContextCompat.getMainExecutor(context)) { event ->
                    mutableState.update {
                        it.copy(
                            duration = event.recordingStats.recordedDurationNanos.nanoseconds,
                            progress = if (maxDuration > Duration.ZERO) {
                                val progressPercent = (event.recordingStats.recordedDurationNanos.toDouble() / maxDuration.inWholeNanoseconds * 100)
                                    .toInt()
                                    .coerceIn(0, 100)

                                progressPercent.percents
                            } else {
                                0.percents
                            }
                        )
                    }

                    when (event) {
                        is VideoRecordEvent.Finalize -> {
                            mutableState.update { it.copy(isRecording = false) }
                            activeRecording = null
                            continuation.resumeWithFinalize(event)
                        }
                    }
                }
        }
    }

    fun cancel() {
        mutableState.update { it.copy(isCancelled = true) }
        activeRecording?.stop()
    }

    fun stop() {
        activeRecording?.stop()
    }

    fun reset() {
        mutableState.update { State() }
    }

    // We want to treat ERROR_FILE_SIZE_LIMIT_REACHED and ERROR_DURATION_LIMIT_REACHED as successful finalization,
    // since they indicate that the recording stopped because it reached the specified limits,
    // which is a valid outcome for our use case
    private fun CancellableContinuation<Unit>.resumeWithFinalize(event: VideoRecordEvent.Finalize) {
        when (event.error) {
            VideoRecordEvent.Finalize.ERROR_NONE,
            VideoRecordEvent.Finalize.ERROR_FILE_SIZE_LIMIT_REACHED,
            VideoRecordEvent.Finalize.ERROR_DURATION_LIMIT_REACHED -> {
                resume(Unit)
            }
            VideoRecordEvent.Finalize.ERROR_UNKNOWN,
            VideoRecordEvent.Finalize.ERROR_INSUFFICIENT_STORAGE,
            VideoRecordEvent.Finalize.ERROR_SOURCE_INACTIVE,
            VideoRecordEvent.Finalize.ERROR_INVALID_OUTPUT_OPTIONS,
            VideoRecordEvent.Finalize.ERROR_ENCODING_FAILED,
            VideoRecordEvent.Finalize.ERROR_RECORDER_ERROR,
            VideoRecordEvent.Finalize.ERROR_NO_VALID_DATA,
            VideoRecordEvent.Finalize.ERROR_RECORDING_GARBAGE_COLLECTED -> {
                resumeWithException(IllegalStateException("Recording failed with error code: ${event.error}"))
            }
        }
    }

    data class State(
        val isRecording: Boolean = false,
        val isCancelled: Boolean = false,
        val progress: Fraction = 0.percents,
        val duration: Duration = Duration.ZERO,
    )
}
