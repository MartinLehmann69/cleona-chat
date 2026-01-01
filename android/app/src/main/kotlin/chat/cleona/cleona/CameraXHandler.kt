package chat.cleona.cleona

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * CameraX handler for video capture during calls.
 *
 * Provides a MethodChannel API for Dart to control the camera:
 * - startCapture(width, height, fps, facing) → starts YUV frame capture
 * - stopCapture() → stops capture
 * - switchCamera() → toggles front/back
 * - isAvailable() → checks camera availability
 *
 * YUV frames (I420) are sent back to Dart via a separate EventChannel
 * or by writing to a shared buffer. For simplicity, frames are sent
 * as byte arrays via MethodChannel callbacks.
 */
class CameraXHandler(
    private val activity: Activity,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "chat.cleona/camera"
        private const val CAMERA_PERMISSION_CODE = 1002
    }

    private var cameraProvider: ProcessCameraProvider? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var camera: Camera? = null
    private var cameraExecutor: ExecutorService? = null
    private var useFrontCamera = true
    private var capturing = false

    // Frame callback to Dart
    private var frameCallback: ((ByteArray, Int, Int) -> Unit)? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> {
                val hasCamera = activity.packageManager.hasSystemFeature(
                    PackageManager.FEATURE_CAMERA_ANY
                )
                result.success(hasCamera)
            }
            "requestPermission" -> {
                if (hasCameraPermission()) {
                    result.success(true)
                } else {
                    ActivityCompat.requestPermissions(
                        activity,
                        arrayOf(Manifest.permission.CAMERA),
                        CAMERA_PERMISSION_CODE
                    )
                    // Permission result will be handled asynchronously
                    result.success(false)
                }
            }
            "startCapture" -> {
                val width = call.argument<Int>("width") ?: 640
                val height = call.argument<Int>("height") ?: 480
                val facing = call.argument<String>("facing") ?: "front"
                useFrontCamera = facing == "front"
                startCapture(width, height, result)
            }
            "stopCapture" -> {
                stopCapture()
                result.success(true)
            }
            "switchCamera" -> {
                useFrontCamera = !useFrontCamera
                if (capturing) {
                    stopCapture()
                    startCapture(
                        imageAnalysis?.resolutionInfo?.resolution?.width ?: 640,
                        imageAnalysis?.resolutionInfo?.resolution?.height ?: 480,
                        result
                    )
                } else {
                    result.success(true)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun hasCameraPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            activity, Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun startCapture(width: Int, height: Int, result: MethodChannel.Result) {
        if (!hasCameraPermission()) {
            result.error("NO_PERMISSION", "Camera permission not granted", null)
            return
        }

        val cameraProviderFuture = ProcessCameraProvider.getInstance(activity)
        cameraProviderFuture.addListener({
            try {
                cameraProvider = cameraProviderFuture.get()
                cameraExecutor = Executors.newSingleThreadExecutor()

                // Configure image analysis (YUV frames)
                imageAnalysis = ImageAnalysis.Builder()
                    .setTargetResolution(android.util.Size(width, height))
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
                    .build()
                    .also { analysis ->
                        analysis.setAnalyzer(cameraExecutor!!) { imageProxy ->
                            processFrame(imageProxy)
                        }
                    }

                // Select camera
                val cameraSelector = if (useFrontCamera) {
                    CameraSelector.DEFAULT_FRONT_CAMERA
                } else {
                    CameraSelector.DEFAULT_BACK_CAMERA
                }

                // Unbind existing use cases and bind new ones
                cameraProvider?.unbindAll()
                camera = cameraProvider?.bindToLifecycle(
                    activity as LifecycleOwner,
                    cameraSelector,
                    imageAnalysis
                )

                capturing = true
                result.success(true)
            } catch (e: Exception) {
                result.error("CAMERA_ERROR", "Failed to start camera: ${e.message}", null)
            }
        }, ContextCompat.getMainExecutor(activity))
    }

    private fun processFrame(imageProxy: ImageProxy) {
        if (!capturing) {
            imageProxy.close()
            return
        }

        try {
            // Convert YUV_420_888 to I420 byte array
            val i420 = yuv420ToI420(imageProxy)
            val width = imageProxy.width
            val height = imageProxy.height

            // Send to Dart via method channel on main thread
            activity.runOnUiThread {
                if (capturing) {
                    channel.invokeMethod("onFrame", mapOf(
                        "data" to i420,
                        "width" to width,
                        "height" to height,
                    ))
                }
            }
        } catch (_: Exception) {
            // Frame processing error — skip frame
        } finally {
            imageProxy.close()
        }
    }

    /**
     * Convert YUV_420_888 ImageProxy to I420 byte array.
     * I420 layout: [Y plane][U plane][V plane]
     * Size: width * height * 3 / 2
     */
    private fun yuv420ToI420(image: ImageProxy): ByteArray {
        val w = image.width
        val h = image.height
        val ySize = w * h
        val uvSize = ySize / 4
        val i420 = ByteArray(ySize + uvSize * 2)

        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]

        val yBuffer = yPlane.buffer
        val uBuffer = uPlane.buffer
        val vBuffer = vPlane.buffer

        val yRowStride = yPlane.rowStride
        val uvRowStride = uPlane.rowStride
        val uvPixelStride = uPlane.pixelStride

        // Copy Y plane
        if (yRowStride == w) {
            yBuffer.get(i420, 0, ySize)
        } else {
            for (row in 0 until h) {
                yBuffer.position(row * yRowStride)
                yBuffer.get(i420, row * w, w)
            }
        }

        // Copy U and V planes (may be interleaved as NV12/NV21)
        val uvH = h / 2
        val uvW = w / 2

        if (uvPixelStride == 1 && uvRowStride == uvW) {
            // Planar — direct copy
            uBuffer.position(0)
            uBuffer.get(i420, ySize, uvSize)
            vBuffer.position(0)
            vBuffer.get(i420, ySize + uvSize, uvSize)
        } else {
            // Interleaved (NV12/NV21) — extract U and V separately
            for (row in 0 until uvH) {
                for (col in 0 until uvW) {
                    val uvIdx = row * uvRowStride + col * uvPixelStride
                    i420[ySize + row * uvW + col] = uBuffer.get(uvIdx)
                    i420[ySize + uvSize + row * uvW + col] = vBuffer.get(uvIdx)
                }
            }
        }

        return i420
    }

    fun stopCapture() {
        capturing = false
        cameraProvider?.unbindAll()
        cameraExecutor?.shutdown()
        cameraExecutor = null
    }

    fun dispose() {
        stopCapture()
        channel.setMethodCallHandler(null)
    }
}
