package com.keylink.keylink_mobile

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        val audioPlayer = KemoAudioPlayer()
        val micRecorder = KemoMicRecorder()
        var methodChannel: MethodChannel? = null

        fun notifyMuteChanged(isMuted: Boolean) {
            try {
                methodChannel?.invokeMethod("onAudioMuteChanged", mapOf("isMuted" to isMuted))
            } catch (_: Exception) {}
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.mobilekemo/background")
        methodChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startKeepAliveService" -> {
                    try {
                        val pcName = call.argument<String>("pc_name") ?: "Desktop PC"

                        // Request notification permission if Android 13+ (API 33+)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 101)
                            }
                        }

                        val intent = Intent(this, KemoKeepAliveService::class.java).apply {
                            action = KemoKeepAliveService.ACTION_START
                            putExtra(KemoKeepAliveService.EXTRA_PC_NAME, pcName)
                        }

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "stopKeepAliveService" -> {
                    try {
                        val intent = Intent(this, KemoKeepAliveService::class.java).apply {
                            action = KemoKeepAliveService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "setAudioMuted" -> {
                    try {
                        val isMuted = call.argument<Boolean>("isMuted") ?: false
                        audioPlayer.setMute(isMuted)
                        KemoKeepAliveService.updateMuteState(this, isMuted)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "isIgnoringBatteryOptimizations" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                            result.success(powerManager?.isIgnoringBatteryOptimizations(packageName) ?: true)
                        } else {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "requestIgnoreBatteryOptimizations" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                            if (powerManager?.isIgnoringBatteryOptimizations(packageName) == false) {
                                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                    data = Uri.parse("package:$packageName")
                                }
                                startActivity(intent)
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "playAudioChunk" -> {
                    try {
                        val pcm = call.argument<ByteArray>("data")
                        val sampleRate = call.argument<Int>("sampleRate") ?: 48000
                        val channels = call.argument<Int>("channels") ?: 2
                        if (pcm != null && pcm.isNotEmpty()) {
                            audioPlayer.write(pcm, sampleRate, channels)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("AUDIO_ERROR", e.message, null)
                    }
                }
                "stopAudio" -> {
                    try {
                        audioPlayer.stop()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("AUDIO_ERROR", e.message, null)
                    }
                }
                "startMicRecording" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                                requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), 102)
                                result.success(false)
                                return@setMethodCallHandler
                            }
                        }
                        val sampleRate = call.argument<Int>("sampleRate") ?: 16000
                        val success = micRecorder.start(sampleRate) { pcmChunk ->
                            runOnUiThread {
                                if (micRecorder.isRecording()) {
                                    methodChannel?.invokeMethod("onMicChunk", mapOf("data" to pcmChunk, "sampleRate" to sampleRate, "channels" to 1))
                                }
                            }
                        }
                        result.success(success)
                    } catch (e: Exception) {
                        result.error("MIC_ERROR", e.message, null)
                    }
                }
                "stopMicRecording" -> {
                    try {
                        micRecorder.stop()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("MIC_ERROR", e.message, null)
                    }
                }
                "isMicRecording" -> {
                    result.success(micRecorder.isRecording())
                }
                "acquireWakeLock" -> {
                    try {
                        if (wakeLock == null) {
                            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                            wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MobileKemo::WakeLock")
                            wakeLock?.setReferenceCounted(false)
                        }
                        if (wakeLock?.isHeld != true) {
                            wakeLock?.acquire(12 * 60 * 60 * 1000L) // 12 hours
                        }

                        if (wifiLock == null) {
                            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                            @Suppress("DEPRECATION")
                            wifiLock = wifiManager.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "MobileKemo::WifiLock")
                            wifiLock?.setReferenceCounted(false)
                        }
                        if (wifiLock?.isHeld != true) {
                            wifiLock?.acquire()
                        }

                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "releaseWakeLock" -> {
                    try {
                        if (wakeLock?.isHeld == true) {
                            wakeLock?.release()
                        }
                        if (wifiLock?.isHeld == true) {
                            wifiLock?.release()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 102 && grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            methodChannel?.invokeMethod("onMicPermissionGranted", null)
        }
    }

    override fun onDestroy() {
        try {
            micRecorder.stop()
            audioPlayer.stop()
            if (wakeLock?.isHeld == true) wakeLock?.release()
            if (wifiLock?.isHeld == true) wifiLock?.release()
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
