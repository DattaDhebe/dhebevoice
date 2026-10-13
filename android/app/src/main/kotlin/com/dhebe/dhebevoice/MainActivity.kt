package com.dhebe.dhebevoice

import android.Manifest
import android.content.pm.PackageManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val notificationPermissionRequestCode = 2026

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!flutterEngine.plugins.has(OfflineTtsPlugin::class.java)) {
            flutterEngine.plugins.add(OfflineTtsPlugin())
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.dhebe.dhebevoice/system"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "ensurePlaybackChannel" -> {
                    val channelId = call.argument<String>("id")
                    val channelName = call.argument<String>("name")
                    val channelDescription = call.argument<String>("description")

                    if (channelId.isNullOrBlank() || channelName.isNullOrBlank()) {
                        result.error(
                            "invalid_args",
                            "Playback channel id and name are required.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    ensurePlaybackChannel(
                        channelId = channelId,
                        channelName = channelName,
                        channelDescription = channelDescription
                    )
                    result.success(null)
                }

                "ensureNotificationPermission" -> {
                    result.success(ensureNotificationPermission())
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun ensureNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true
        }

        val alreadyGranted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED

        if (alreadyGranted) {
            return true
        }

        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode
        )
        return false
    }

    private fun ensurePlaybackChannel(
        channelId: String,
        channelName: String,
        channelDescription: String?
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val notificationManager = getSystemService(NotificationManager::class.java)
            ?: return

        val channel = NotificationChannel(
            channelId,
            channelName,
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = channelDescription.orEmpty()
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }

        notificationManager.createNotificationChannel(channel)
    }
}
