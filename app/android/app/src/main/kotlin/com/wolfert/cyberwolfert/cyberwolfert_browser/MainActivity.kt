package com.wolfert.cyberwolfert.cyberwolfert_browser

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "cyberwolfert/updater"
    private val voiceChannelName = "cyberwolfert/voice"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Altijd-aan luisterdienst + trillen (Hey Nova / inkomend gesprek).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, voiceChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        try {
                            val i = Intent(this, VoiceService::class.java)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(i)
                            } else {
                                startService(i)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("start", e.message, null)
                        }
                    }
                    "stop" -> {
                        try {
                            stopService(Intent(this, VoiceService::class.java))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("stop", e.message, null)
                        }
                    }
                    "vibrate" -> {
                        val ms = (call.argument<Number>("ms") ?: 300).toLong()
                        try {
                            vibrate(ms)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("vibrate", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // APK naar de publieke Downloadmap: het bestand blijft bewaard,
                    // ook als de gebruiker daarna de app verwijdert.
                    "downloadApk" -> {
                        val url = call.argument<String>("url") ?: ""
                        if (url.isEmpty()) {
                            result.error("geen_url", "geen downloadadres", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                            File(
                                Environment.getExternalStoragePublicDirectory(
                                    Environment.DIRECTORY_DOWNLOADS
                                ), "CyberWolfert.apk"
                            ).delete()
                            val req = DownloadManager.Request(Uri.parse(url))
                                .setTitle("CyberWolfert update")
                                .setDescription("Nieuwe versie wordt gedownload\u2026")
                                .setMimeType("application/vnd.android.package-archive")
                                .setDestinationInExternalPublicDir(
                                    Environment.DIRECTORY_DOWNLOADS,
                                    "CyberWolfert.apk"
                                )
                                .setNotificationVisibility(
                                    DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
                                )
                            result.success(dm.enqueue(req))
                        } catch (e: Exception) {
                            result.error("download", e.message, null)
                        }
                    }
                    // Systeem-vraag om deze app te verwijderen (nieuwe tekening past
                    // niet over de oude heen). De APK-download loopt gewoon door.
                    "uninstallSelf" -> {
                        try {
                            val i = Intent(Intent.ACTION_DELETE, Uri.parse("package:$packageName"))
                            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(i)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("verwijderen", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun vibrate(ms: Long) {
        val amplitude = 120
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vm.defaultVibrator.vibrate(
                VibrationEffect.createOneShot(ms, amplitude)
            )
        } else {
            val v = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                v.vibrate(VibrationEffect.createOneShot(ms, amplitude))
            } else {
                v.vibrate(ms)
            }
        }
    }
}
