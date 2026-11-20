package com.keylink.keylink_mobile

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build

class KemoAudioPlayer {
    @Volatile
    var isMuted: Boolean = false

    private var audioTrack: AudioTrack? = null
    private var currentSampleRate = 0
    private var currentChannels = 0
    private var isPlaying = false

    @Synchronized
    fun setMute(muted: Boolean) {
        isMuted = muted
        if (muted) {
            try {
                audioTrack?.pause()
                audioTrack?.flush()
            } catch (_: Exception) {}
        } else {
            try {
                audioTrack?.play()
            } catch (_: Exception) {}
        }
    }

    @Synchronized
    fun start(sampleRate: Int, channels: Int) {
        if (isPlaying && currentSampleRate == sampleRate && currentChannels == channels && audioTrack != null) {
            return
        }
        stop()

        currentSampleRate = sampleRate
        currentChannels = channels

        val channelConfig = if (channels == 1) {
            AudioFormat.CHANNEL_OUT_MONO
        } else {
            AudioFormat.CHANNEL_OUT_STEREO
        }

        val minBufSize = AudioTrack.getMinBufferSize(
            sampleRate,
            channelConfig,
            AudioFormat.ENCODING_PCM_16BIT
        )
        // Set buffer to ~80ms to provide smooth jitter-free playback with ultra-low latency
        val bufferSize = (minBufSize * 2).coerceAtLeast(sampleRate * channels * 2 * 8 / 100)

        audioTrack = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(channelConfig)
                        .build()
                )
                .setBufferSizeInBytes(bufferSize)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
        } else {
            @Suppress("DEPRECATION")
            AudioTrack(
                AudioManager.STREAM_MUSIC,
                sampleRate,
                channelConfig,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize,
                AudioTrack.MODE_STREAM
            )
        }

        try {
            audioTrack?.play()
            isPlaying = true
        } catch (_: Exception) {}
    }

    @Synchronized
    fun write(pcmData: ByteArray, sampleRate: Int, channels: Int) {
        if (isMuted) {
            return
        }
        if (!isPlaying || currentSampleRate != sampleRate || currentChannels != channels || audioTrack == null) {
            start(sampleRate, channels)
        }
        try {
            audioTrack?.write(pcmData, 0, pcmData.size)
        } catch (_: Exception) {}
    }

    @Synchronized
    fun stop() {
        isPlaying = false
        try {
            audioTrack?.pause()
            audioTrack?.flush()
            audioTrack?.stop()
            audioTrack?.release()
        } catch (_: Exception) {}
        audioTrack = null
    }
}
