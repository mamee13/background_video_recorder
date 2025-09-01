package com.example.background_video_recorder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.hardware.camera2.*
import android.media.CamcorderProfile
import android.media.MediaRecorder
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.*
import android.provider.MediaStore
import android.util.Log
import android.view.Surface
import androidx.core.app.NotificationCompat
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class ForegroundVideoService : Service() {

    companion object {
        const val CHANNEL_ID = "recording_channel"
        const val CHANNEL_NAME = "Background Recording"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "com.example.background_video_recorder.action.START"
        const val ACTION_STOP = "com.example.background_video_recorder.action.STOP"
        const val EXTRA_CAMERA_FACING = "camera_facing" // "back" or "front"
        const val EXTRA_QUALITY = "quality" // e.g., 720, 1080
    }

    private lateinit var notificationManager: NotificationManager
    private lateinit var cameraManager: CameraManager

    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var mediaRecorder: MediaRecorder? = null
    private var recordingSurface: Surface? = null

    private var wakeLock: PowerManager.WakeLock? = null

    // Output tracking
    private var outputUri: Uri? = null
    private var outputPfd: ParcelFileDescriptor? = null
    private var outputFile: File? = null
    private var outputDisplayName: String? = null

    override fun onBind(intent: Intent?) = null

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                startForeground(NOTIFICATION_ID, buildNotification("Recording in background"))
                acquireWakeLock()
                val facing = intent.getStringExtra(EXTRA_CAMERA_FACING) ?: "back"
                val quality = intent.getIntExtra(EXTRA_QUALITY, 1080)
                startRecording(facing, quality)
            }
            ACTION_STOP -> {
                stopRecording()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            else -> {
                startForeground(NOTIFICATION_ID, buildNotification("Recording in background"))
                acquireWakeLock()
                startRecording("back", 1080)
            }
        }
        return START_NOT_STICKY
    }

    private fun startRecording(facing: String, quality: Int) {
        try {
            val cameraId = selectCameraId(facing)
            if (cameraId == null) {
                Log.e("BVR", "No suitable camera found")
                updateNotification("Camera unavailable")
                return
            }
            prepareMediaRecorder(cameraId, quality)
            val surfaces = mutableListOf<Surface>()
            recordingSurface = mediaRecorder!!.surface
            surfaces.add(recordingSurface!!)

            val stateCallback = object : CameraDevice.StateCallback() {
                override fun onOpened(device: CameraDevice) {
                    cameraDevice = device
                    createRecordSession(device, surfaces)
                }

                override fun onDisconnected(device: CameraDevice) {
                    Log.w("BVR", "Camera disconnected")
                    device.close()
                    cameraDevice = null
                }

                override fun onError(device: CameraDevice, error: Int) {
                    Log.e("BVR", "Camera error: $error")
                    device.close()
                    cameraDevice = null
                    updateNotification("Camera error: $error")
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val handlerThread = HandlerThread("bvr_camera")
                handlerThread.start()
                val handler = Handler(handlerThread.looper)
                cameraManager.openCamera(cameraId, stateCallback, handler)
            } else {
                cameraManager.openCamera(cameraId, stateCallback, null)
            }
        } catch (se: SecurityException) {
            Log.e("BVR", "Missing camera/mic permissions: ${se.message}")
            updateNotification("Missing permissions")
        } catch (e: Exception) {
            Log.e("BVR", "startRecording error: ${e.message}", e)
            updateNotification("Failed to start recording")
        }
    }

    private fun createRecordSession(device: CameraDevice, surfaces: List<Surface>) {
        try {
            device.createCaptureSession(
                surfaces,
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        captureSession = session
                        try {
                            val requestBuilder = device.createCaptureRequest(CameraDevice.TEMPLATE_RECORD)
                            for (surface in surfaces) requestBuilder.addTarget(surface)
                            requestBuilder.set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
                            session.setRepeatingRequest(requestBuilder.build(), null, null)
                            mediaRecorder?.start()
                            val where = outputDisplayName?.let { name ->
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) "Saved to Movies/BackgroundVideoRecorder/$name"
                                else outputFile?.absolutePath ?: "Recording..."
                            } ?: "Recording..."
                            updateNotification("Recording... Tap to stop. $where")
                        } catch (e: Exception) {
                            Log.e("BVR", "Failed to start capture session: ${e.message}", e)
                            updateNotification("Failed to start camera session")
                            stopRecording()
                        }
                    }

                    override fun onConfigureFailed(session: CameraCaptureSession) {
                        Log.e("BVR", "Capture session configuration failed")
                        updateNotification("Camera session failed")
                        stopRecording()
                    }
                },
                null
            )
        } catch (e: Exception) {
            Log.e("BVR", "createRecordSession error: ${e.message}", e)
            updateNotification("Failed to start recording")
            stopRecording()
        }
    }

    private fun prepareMediaRecorder(cameraId: String, quality: Int) {
        mediaRecorder = MediaRecorder()
        mediaRecorder!!.reset()
        mediaRecorder!!.setAudioSource(MediaRecorder.AudioSource.MIC)
        mediaRecorder!!.setVideoSource(MediaRecorder.VideoSource.SURFACE)
        mediaRecorder!!.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)

        val displayName = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date()).let { "VID_${it}.mp4" }
        outputDisplayName = displayName
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Save to public Movies/BackgroundVideoRecorder so it shows in Gallery
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, displayName)
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/BackgroundVideoRecorder")
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
            outputUri = uri
            if (uri == null) throw IllegalStateException("Failed to create MediaStore record")
            outputPfd = contentResolver.openFileDescriptor(uri, "w")
            if (outputPfd == null) throw IllegalStateException("Failed to open output FD")
            mediaRecorder!!.setOutputFile(outputPfd!!.fileDescriptor)
        } else {
            // Fallback: app-scoped Movies directory
            val moviesDir = getExternalFilesDir(Environment.DIRECTORY_MOVIES) ?: filesDir
            if (!moviesDir.exists()) moviesDir.mkdirs()
            val file = File(moviesDir, displayName)
            outputFile = file
            mediaRecorder!!.setOutputFile(file.absolutePath)
        }

        val numericId = cameraId.toIntOrNull() ?: 0
        val profile = when {
            CamcorderProfile.hasProfile(numericId, CamcorderProfile.QUALITY_1080P) && quality >= 1080 -> CamcorderProfile.get(numericId, CamcorderProfile.QUALITY_1080P)
            CamcorderProfile.hasProfile(numericId, CamcorderProfile.QUALITY_720P) && quality >= 720 -> CamcorderProfile.get(numericId, CamcorderProfile.QUALITY_720P)
            CamcorderProfile.hasProfile(numericId, CamcorderProfile.QUALITY_480P) -> CamcorderProfile.get(numericId, CamcorderProfile.QUALITY_480P)
            else -> null
        }

        if (profile != null) {
            mediaRecorder!!.setVideoEncodingBitRate(profile.videoBitRate)
            mediaRecorder!!.setVideoFrameRate(profile.videoFrameRate)
            mediaRecorder!!.setVideoSize(profile.videoFrameWidth, profile.videoFrameHeight)
            mediaRecorder!!.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            mediaRecorder!!.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            mediaRecorder!!.setAudioEncodingBitRate(profile.audioBitRate)
            mediaRecorder!!.setAudioSamplingRate(profile.audioSampleRate)
        } else {
            // Fallback settings
            mediaRecorder!!.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            mediaRecorder!!.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            mediaRecorder!!.setVideoEncodingBitRate(5_000_000)
            mediaRecorder!!.setVideoFrameRate(30)
            mediaRecorder!!.setVideoSize(1280, 720)
            mediaRecorder!!.setAudioEncodingBitRate(128_000)
            mediaRecorder!!.setAudioSamplingRate(44_100)
        }

        setOrientationHint(cameraId)
        mediaRecorder!!.prepare()
    }

    private fun setOrientationHint(cameraId: String) {
        try {
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            val sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
            mediaRecorder?.setOrientationHint(sensorOrientation)
        } catch (_: Exception) {
        }
    }

    private fun selectCameraId(facing: String): String? {
        try {
            for (id in cameraManager.cameraIdList) {
                val chars = cameraManager.getCameraCharacteristics(id)
                val lensFacing = chars.get(CameraCharacteristics.LENS_FACING)
                if (facing == "front" && lensFacing == CameraCharacteristics.LENS_FACING_FRONT) return id
                if (facing == "back" && lensFacing == CameraCharacteristics.LENS_FACING_BACK) return id
            }
            return cameraManager.cameraIdList.firstOrNull()
        } catch (e: Exception) {
            Log.e("BVR", "selectCameraId error: ${e.message}", e)
        }
        return null
    }

    private fun stopRecording() {
        // Stop capture and recorder safely
        try { captureSession?.stopRepeating() } catch (_: Exception) {}
        try { captureSession?.abortCaptures() } catch (_: Exception) {}
        try { mediaRecorder?.setOnErrorListener(null) } catch (_: Exception) {}
        try { mediaRecorder?.setOnInfoListener(null) } catch (_: Exception) {}
        try { mediaRecorder?.stop() } catch (_: Exception) {}
        try { mediaRecorder?.reset() } catch (_: Exception) {}
        try { mediaRecorder?.release() } catch (_: Exception) {}
        mediaRecorder = null

        try { cameraDevice?.close() } catch (_: Exception) {}
        cameraDevice = null
        captureSession = null

        try { recordingSurface?.release() } catch (_: Exception) {}
        recordingSurface = null

        // Finalize output
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && outputUri != null) {
                val values = ContentValues().apply { put(MediaStore.Video.Media.IS_PENDING, 0) }
                contentResolver.update(outputUri!!, values, null, null)
            } else if (outputFile != null) {
                MediaScannerConnection.scanFile(
                    this,
                    arrayOf(outputFile!!.absolutePath),
                    arrayOf("video/mp4")
                ) { _, _ -> }
            }
        } catch (e: Exception) {
            Log.w("BVR", "Finalize output failed: ${e.message}")
        }

        // Close PFD if any
        try { outputPfd?.close() } catch (_: Exception) {}
        outputPfd = null

        val where = outputDisplayName?.let { name ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) "Movies/BackgroundVideoRecorder/$name"
            else outputFile?.absolutePath ?: ""
        } ?: ""
        updateNotification(if (where.isNotEmpty()) "Recording stopped: $where" else "Recording stopped")

        releaseWakeLock()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW)
            channel.description = "Background video recording"
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(contentText: String): Notification {
        val stopIntent = Intent(this, ForegroundVideoService::class.java).apply { action = ACTION_STOP }
        val flags = PendingIntent.FLAG_CANCEL_CURRENT or (if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0)
        val stopPendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(this, 1002, stopIntent, flags)
        } else {
            PendingIntent.getService(this, 1002, stopIntent, flags)
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Background Video Recorder")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.presence_video_online)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPendingIntent)
            .build()
    }

    private fun updateNotification(contentText: String) {
        notificationManager.notify(NOTIFICATION_ID, buildNotification(contentText))
    }

    private fun acquireWakeLock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "BVR:RecorderWakelock").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (e: Exception) {
            Log.w("BVR", "Failed to acquire wakelock: ${e.message}")
        }
    }

    private fun releaseWakeLock() {
        try { wakeLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        wakeLock = null
    }

    override fun onDestroy() {
        super.onDestroy()
        stopRecording()
    }
}