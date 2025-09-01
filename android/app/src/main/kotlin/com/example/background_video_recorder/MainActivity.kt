package com.example.background_video_recorder

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
                else -> result.notImplemented()
            }
        }
    }
}
