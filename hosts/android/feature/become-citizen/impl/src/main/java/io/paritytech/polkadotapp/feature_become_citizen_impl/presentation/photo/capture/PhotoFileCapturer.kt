package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.capture

import android.content.Context
import android.util.Size
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.SurfaceRequest
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.common.utils.camera.CameraBinder
import kotlinx.coroutines.suspendCancellableCoroutine
import java.io.File
import javax.inject.Inject
import kotlin.coroutines.resume

private val TARGET_RESOLUTION: Size = Size(1920, 1200)
private const val TARGET_JPEG_QUALITY = 80

class PhotoFileCapturer @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val cameraBinder: CameraBinder
) {
    private val imageCapture: ImageCapture

    init {
        val resolutionSelector = ResolutionSelector.Builder()
            .setResolutionStrategy(ResolutionStrategy(TARGET_RESOLUTION, ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER))
            .build()

        imageCapture = ImageCapture.Builder()
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
            .setJpegQuality(TARGET_JPEG_QUALITY)
            .setResolutionSelector(resolutionSelector)
            .build()
    }

    suspend fun bind(
        lifecycleOwner: LifecycleOwner,
        surfaceRequest: (SurfaceRequest) -> Unit
    ) {
        cameraBinder.bind(lifecycleOwner, surfaceRequest, imageCapture)
    }

    suspend fun takePicture(outputFile: File): Result<Unit> = suspendCancellableCoroutine { continuation ->
        val outputOptions = ImageCapture.OutputFileOptions.Builder(outputFile).build()

        imageCapture.takePicture(
            outputOptions,
            ContextCompat.getMainExecutor(context),
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                    continuation.resume(Result.success(Unit))
                }

                override fun onError(exc: ImageCaptureException) {
                    continuation.resume(Result.failure(exc))
                }
            }
        )
    }
}
