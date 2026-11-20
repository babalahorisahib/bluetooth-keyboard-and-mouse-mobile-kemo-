package com.keylink.keylink_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

class KemoKeepAliveService : Service() {
    companion object {
        const val CHANNEL_ID = "kemo_active_connection"
        const val CHANNEL_NAME = "Mobile Kemo Background Connection"
        const val NOTIFICATION_ID = 90210
        const val ACTION_START = "com.mobilekemo.START_KEEP_ALIVE"
        const val ACTION_STOP = "com.mobilekemo.STOP_KEEP_ALIVE"
        const val ACTION_TOGGLE_MUTE = "com.mobilekemo.TOGGLE_MUTE"
        const val ACTION_SET_MUTE = "com.mobilekemo.SET_MUTE"
        const val EXTRA_PC_NAME = "extra_pc_name"
        const val EXTRA_IS_MUTED = "extra_is_muted"

        @Volatile
        var isAudioMuted: Boolean = false

        fun updateMuteState(context: Context, muted: Boolean) {
            isAudioMuted = muted
            val intent = Intent(context, KemoKeepAliveService::class.java).apply {
                action = ACTION_SET_MUTE
                putExtra(EXTRA_IS_MUTED, muted)
            }
            try {
                context.startService(intent)
            } catch (_: Exception) {}
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var lastPcName: String = "Desktop PC"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps connection active with PC while using other apps"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(pcName: String, muted: Boolean): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName) ?: Intent(this, MainActivity::class.java)
        launchIntent.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP

        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            pendingIntentFlags
        )

        // PendingIntent for Mute / Unmute button in notification
        val muteIntent = Intent(this, KemoKeepAliveService::class.java).apply {
            action = ACTION_TOGGLE_MUTE
        }
        val mutePendingIntent = PendingIntent.getService(
            this,
            1,
            muteIntent,
            pendingIntentFlags
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val muteActionTitle = if (muted) "🔊 Unmute Audio" else "🔇 Mute Audio"

        @Suppress("DEPRECATION")
        val muteAction = Notification.Action.Builder(
            android.R.drawable.ic_lock_silent_mode,
            muteActionTitle,
            mutePendingIntent
        ).build()

        builder.setContentTitle("Mobile Kemo Connected")
            .setContentText("Connected to $pcName — Tap to return")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .addAction(muteAction)
            .setOngoing(true)
            .setAutoCancel(false)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }

        return builder.build()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        if (action == ACTION_STOP) {
            releaseLocks()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
            return START_NOT_STICKY
        }

        if (intent?.hasExtra(EXTRA_PC_NAME) == true) {
            lastPcName = intent.getStringExtra(EXTRA_PC_NAME) ?: lastPcName
        }

        if (action == ACTION_TOGGLE_MUTE) {
            isAudioMuted = !isAudioMuted
            MainActivity.audioPlayer.setMute(isAudioMuted)
            MainActivity.notifyMuteChanged(isAudioMuted)
        } else if (action == ACTION_SET_MUTE) {
            isAudioMuted = intent?.getBooleanExtra(EXTRA_IS_MUTED, isAudioMuted) ?: isAudioMuted
            MainActivity.audioPlayer.setMute(isAudioMuted)
        }

        val notification = buildNotification(lastPcName, isAudioMuted)

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        manager?.notify(NOTIFICATION_ID, notification)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (_: Exception) {
            try {
                startForeground(NOTIFICATION_ID, notification)
            } catch (_: Exception) {}
        }

        acquireLocks()
        return START_STICKY
    }

    private fun acquireLocks() {
        try {
            if (wakeLock == null) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                wakeLock = powerManager?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MobileKemo::ServiceWakeLock")
                wakeLock?.setReferenceCounted(false)
            }
            if (wakeLock?.isHeld != true) {
                wakeLock?.acquire(24 * 60 * 60 * 1000L) // 24 hours
            }

            if (wifiLock == null) {
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                @Suppress("DEPRECATION")
                wifiLock = wifiManager?.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "MobileKemo::ServiceWifiLock")
                wifiLock?.setReferenceCounted(false)
            }
            if (wifiLock?.isHeld != true) {
                wifiLock?.acquire()
            }
        } catch (_: Exception) {}
    }

    private fun releaseLocks() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
            if (wifiLock?.isHeld == true) wifiLock?.release()
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        releaseLocks()
        super.onDestroy()
    }
}
