package com.wolfert.cyberwolfert.cyberwolfert_browser

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/// Altijd-aan luisterdienst: houdt de app "wakker" (foreground service) zodat
/// Hey Nova ook op de achtergrond blijft werken en Android de app niet
/// doodt. Mikrofoontype zodat luisteren op de achtergrond is toegestaan.
class VoiceService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val channelId = "aeroactive"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            val ch = NotificationChannel(
                channelId,
                "AeroSurf actief",
                NotificationManager.IMPORTANCE_LOW
            )
            ch.setShowBadge(false)
            ch.description = "Houdt Hey Nova wakker zodat je altijd kunt praten"
            nm.createNotificationChannel(ch)
        }

        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pending = PendingIntent.getActivity(
            this, 0, launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notif = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("AeroSurf luistert mee")
            .setContentText("Zeg \"Hey Nova\" of \"Oke Nova\" om te praten.")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setContentIntent(pending)
            .setShowWhen(false)
            .build()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                startForeground(
                    42, notif,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                )
            } else {
                startForeground(42, notif)
            }
        } catch (e: Exception) {
            // Zonder microfoontype (bijv. fabrikant-beperking): gewoon starten.
            try {
                startForeground(42, notif)
            } catch (_: Exception) {
            }
        }
        return START_STICKY
    }
}
