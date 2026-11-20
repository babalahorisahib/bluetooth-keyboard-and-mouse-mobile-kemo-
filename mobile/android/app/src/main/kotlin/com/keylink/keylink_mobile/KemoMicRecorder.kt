package com.keylink.keylink_mobile

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import java.util.concurrent.atomic.AtomicBoolean

class KemoMicRecorder {
    private var audioRecord: AudioRecord? = null
    private var recordingThread: Thread? = null
    private val isRecording = AtomicBoolean(false)

    @SuppressLint("MissingPermission")
    @Synchronized
    fun start(sampleRate: Int = 16000, onAudioChunk: (ByteArray) -> Unit): Boolean {
        if (isRecording.get()) {
            return true
        }

        try {
            val channelConfig = AudioFormat.CHANNEL_IN_MONO
            val audioFormat = AudioFormat.ENCODING_PCM_16BIT
            val minBufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
            if (minBufferSize <= 0) {
                return false
            }

            val bufferSize = maxOf(minBufferSize * 2, 4096)
            // 50ms chunks at 16kHz 16-bit mono: 16000 * 0.05 * 2 = 1600 bytes (800 samples)
            val chunkSize = (sampleRate * 50 / 1000) * 2

            val sources = intArrayOf(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                MediaRecorder.AudioSource.MIC,
                MediaRecorder.AudioSource.DEFAULT
            )

            var record: AudioRecord? = null
            for (src in sources) {
                try {
                    val candidate = AudioRecord(src, sampleRate, channelConfig, audioFormat, bufferSize)
                    if (candidate.state == AudioRecord.STATE_INITIALIZED) {
                        record = candidate
                        break
                    } else {
                        candidate.release()
                    }
                } catch (_: Exception) {}
            }

            if (record == null) {
                return false
            }

            record.startRecording()
            audioRecord = record
            isRecording.set(true)

            recordingThread = Thread({
                val buffer = ByteArray(chunkSize)
                while (isRecording.get()) {
                    val readBytes = record.read(buffer, 0, chunkSize)
                    if (readBytes > 0) {
                        val chunkCopy = buffer.copyOf(readBytes)
                        onAudioChunk(chunkCopy)
                    } else if (readBytes < 0) {
                        break
                    }
                }
            }, "KemoMicRecordingThread").apply {
                priority = Thread.MAX_PRIORITY
                start()
            }

            return true
        } catch (e: Exception) {
            stop()
            return false
        }
    }

    @Synchronized
    fun stop() {
        if (!isRecording.getAndSet(false)) {
            return
        }

        try {
            recordingThread?.interrupt()
            recordingThread = null

            audioRecord?.apply {
                try {
                    stop()
                } catch (_: Exception) {}
                release()
            }
            audioRecord = null
        } catch (_: Exception) {}
    }

    fun isRecording(): Boolean = isRecording.get()
}
