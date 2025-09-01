package com.example.background_video_recorder

import android.content.ContentUris
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "bvr/channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    val facing = call.argument<String>("cameraFacing") ?: "back"
                    val quality = call.argument<Int>("quality") ?: 1080
                    val intent = Intent(this, ForegroundVideoService::class.java).apply {
                        action = ForegroundVideoService.ACTION_START
                        putExtra(ForegroundVideoService.EXTRA_CAMERA_FACING, facing)
                        putExtra(ForegroundVideoService.EXTRA_QUALITY, quality)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
                    result.success(null)
                }
                "stopService" -> {
                    val intent = Intent(this, ForegroundVideoService::class.java).apply { action = ForegroundVideoService.ACTION_STOP }
                    startService(intent)
                    result.success(null)
                }
                "listRecordings" -> {
                    result.success(listRecordings())
                }
                "deleteRecording" -> {
                    val uriStr = call.argument<String>("uri")
                    val path = call.argument<String>("path")
                    val ok = deleteRecording(uriStr, path)
                    result.success(ok)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun listRecordings(): List<Map<String, Any?>> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val out = mutableListOf<Map<String, Any?>>()
            val projection = arrayOf(
                MediaStore.Video.Media._ID,
                MediaStore.Video.Media.DISPLAY_NAME,
                MediaStore.Video.Media.DATE_ADDED,
                MediaStore.Video.Media.SIZE,
                MediaStore.Video.Media.RELATIVE_PATH
            )
            val selection = MediaStore.Video.Media.RELATIVE_PATH + " LIKE ?"
            val args = arrayOf("%" + Environment.DIRECTORY_MOVIES + "/BackgroundVideoRecorder%")
            val sortOrder = MediaStore.Video.Media.DATE_ADDED + " DESC"
            contentResolver.query(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                args,
                sortOrder
            )?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
                val dateCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_ADDED)
                val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idCol)
                    val name = cursor.getString(nameCol)
                    val date = cursor.getLong(dateCol) // seconds since epoch
                    val size = cursor.getLong(sizeCol)
                    val uri: Uri = ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id)
                    out.add(mapOf(
                        "uri" to uri.toString(),
                        "path" to null,
                        "name" to name,
                        "date" to date,
                        "size" to size
                    ))
                }
            }
            out
        } else {
            val out = mutableListOf<Map<String, Any?>>()
            val dir = getExternalFilesDir(Environment.DIRECTORY_MOVIES)
            val files = dir?.listFiles { f -> f.isFile && f.name.endsWith(".mp4", true) }?.sortedByDescending { it.lastModified() }
            files?.forEach { file ->
                out.add(mapOf(
                    "uri" to null,
                    "path" to file.absolutePath,
                    "name" to file.name,
                    "date" to (file.lastModified() / 1000), // seconds
                    "size" to file.length()
                ))
            }
            out
        }
    }

    private fun deleteRecording(uriStr: String?, path: String?): Boolean {
        return try {
            if (uriStr != null) {
                val uri = Uri.parse(uriStr)
                contentResolver.delete(uri, null, null) > 0
            } else if (path != null) {
                val f = File(path)
                f.exists() && f.delete()
            } else {
                false
            }
        } catch (_: Exception) { false }
    }
}