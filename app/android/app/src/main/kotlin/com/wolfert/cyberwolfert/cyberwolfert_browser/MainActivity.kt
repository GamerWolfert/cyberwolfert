package com.wolfert.cyberwolfert.cyberwolfert_browser

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "cyberwolfert/updater"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                                .setDescription("Nieuwe versie wordt gedownload…")
                                .setMimeType("application/vnd.android.package-archive")
                                .setDestinationInExternalPublicDir(
                                    Environment.DIRECTORY_DOWNLOADS, "CyberWolfert.apk"
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
}
