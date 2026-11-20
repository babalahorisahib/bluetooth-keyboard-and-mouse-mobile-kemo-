#![cfg(target_os = "windows")]
#![allow(non_snake_case, dead_code)]

use std::ffi::c_void;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

#[repr(C)]
#[derive(Debug, Copy, Clone)]
struct WAVEFORMATEX {
    wFormatTag: u16,
    nChannels: u16,
    nSamplesPerSec: u32,
    nAvgBytesPerSec: u32,
    nBlockAlign: u16,
    wBitsPerSample: u16,
    cbSize: u16,
}

#[repr(C)]
struct WAVEHDR {
    lpData: *mut u8,
    dwBufferLength: u32,
    dwBytesRecorded: u32,
    dwUser: usize,
    dwFlags: u32,
    dwLoops: u32,
    lpNext: *mut c_void,
    reserved: usize,
}

const WAVE_MAPPER: u32 = 0xFFFFFFFF;
const WAVE_FORMAT_PCM: u16 = 1;
const WHDR_DONE: u32 = 0x00000001;

#[link(name = "winmm")]
extern "system" {
    fn waveOutOpen(
        phwo: *mut usize,
        uDeviceID: u32,
        pwfx: *const WAVEFORMATEX,
        dwCallback: usize,
        dwInstance: usize,
        fdwOpen: u32,
    ) -> u32;
    fn waveOutPrepareHeader(hwo: usize, pwh: *mut WAVEHDR, cbwh: u32) -> u32;
    fn waveOutWrite(hwo: usize, pwh: *mut WAVEHDR, cbwh: u32) -> u32;
    fn waveOutUnprepareHeader(hwo: usize, pwh: *mut WAVEHDR, cbwh: u32) -> u32;
    fn waveOutClose(hwo: usize) -> u32;
    fn waveOutReset(hwo: usize) -> u32;
}

struct InFlightChunk {
    hdr: Box<WAVEHDR>,
    _data: Vec<u8>,
}

enum PlaybackCommand {
    AudioChunk {
        sample_rate: u32,
        channels: u16,
        pcm_data: Vec<u8>,
    },
    Stop,
}

pub struct SystemAudioPlayback {
    tx: Option<Sender<PlaybackCommand>>,
    is_running: Arc<AtomicBool>,
}

impl SystemAudioPlayback {
    pub fn new() -> Self {
        let (tx, rx) = channel::<PlaybackCommand>();
        let is_running = Arc::new(AtomicBool::new(true));
        let running_clone = Arc::clone(&is_running);

        thread::Builder::new()
            .name("kemo_audio_playback_worker".to_string())
            .spawn(move || {
                Self::worker_loop(rx, running_clone);
            })
            .expect("Failed to spawn audio playback worker thread");

        Self {
            tx: Some(tx),
            is_running,
        }
    }

    pub fn play_chunk(&self, sample_rate: u32, channels: u16, pcm_data: Vec<u8>) {
        if let Some(ref tx) = self.tx {
            let _ = tx.send(PlaybackCommand::AudioChunk {
                sample_rate,
                channels,
                pcm_data,
            });
        }
    }

    pub fn stop(&self) {
        if let Some(ref tx) = self.tx {
            let _ = tx.send(PlaybackCommand::Stop);
        }
    }

    fn worker_loop(rx: Receiver<PlaybackCommand>, is_running: Arc<AtomicBool>) {
        let mut hwo: usize = 0;
        let mut current_sample_rate = 0u32;
        let mut current_channels = 0u16;
        let mut in_flight: Vec<InFlightChunk> = Vec::with_capacity(32);
        let mut last_chunk_time = Instant::now();

        while is_running.load(Ordering::Relaxed) {
            match rx.recv_timeout(Duration::from_millis(15)) {
                Ok(PlaybackCommand::AudioChunk { sample_rate, channels, mut pcm_data }) => {
                    last_chunk_time = Instant::now();

                    // If sample rate or channels changed, re-open waveOut
                    if hwo != 0 && (current_sample_rate != sample_rate || current_channels != channels) {
                        unsafe {
                            let _ = waveOutReset(hwo);
                        }
                        for mut item in in_flight.drain(..) {
                            unsafe {
                                let _ = waveOutUnprepareHeader(hwo, &mut *item.hdr, std::mem::size_of::<WAVEHDR>() as u32);
                            }
                        }
                        unsafe {
                            let _ = waveOutClose(hwo);
                        }
                        hwo = 0;
                    }

                    // Open waveOut if not already opened
                    if hwo == 0 {
                        let bits_per_sample = 16u16;
                        let block_align = channels * (bits_per_sample / 8);
                        let avg_bytes_per_sec = sample_rate * (block_align as u32);

                        let wfx = WAVEFORMATEX {
                            wFormatTag: WAVE_FORMAT_PCM,
                            nChannels: channels,
                            nSamplesPerSec: sample_rate,
                            nAvgBytesPerSec: avg_bytes_per_sec,
                            nBlockAlign: block_align,
                            wBitsPerSample: bits_per_sample,
                            cbSize: 0,
                        };

                        let mut new_hwo: usize = 0;
                        let res = unsafe { waveOutOpen(&mut new_hwo, WAVE_MAPPER, &wfx, 0, 0, 0) };
                        if res == 0 {
                            hwo = new_hwo;
                            current_sample_rate = sample_rate;
                            current_channels = channels;
                        } else {
                            continue;
                        }
                    }

                    // Cleanup finished in-flight buffers
                    in_flight.retain_mut(|item| {
                        if (item.hdr.dwFlags & WHDR_DONE) != 0 {
                            unsafe {
                                let _ = waveOutUnprepareHeader(hwo, &mut *item.hdr, std::mem::size_of::<WAVEHDR>() as u32);
                            }
                            false
                        } else {
                            true
                        }
                    });

                    // Avoid latency buildup: if more than 10 chunks (~500ms) in flight, reset device to drop old queue cleanly
                    if in_flight.len() > 10 {
                        unsafe {
                            let _ = waveOutReset(hwo);
                        }
                        for mut item in in_flight.drain(..) {
                            unsafe {
                                let _ = waveOutUnprepareHeader(hwo, &mut *item.hdr, std::mem::size_of::<WAVEHDR>() as u32);
                            }
                        }
                    }

                    // Prepare and write new buffer
                    let mut hdr = Box::new(WAVEHDR {
                        lpData: pcm_data.as_mut_ptr(),
                        dwBufferLength: pcm_data.len() as u32,
                        dwBytesRecorded: 0,
                        dwUser: 0,
                        dwFlags: 0,
                        dwLoops: 0,
                        lpNext: std::ptr::null_mut(),
                        reserved: 0,
                    });

                    unsafe {
                        let prep_res = waveOutPrepareHeader(hwo, &mut *hdr, std::mem::size_of::<WAVEHDR>() as u32);
                        if prep_res == 0 {
                            let write_res = waveOutWrite(hwo, &mut *hdr, std::mem::size_of::<WAVEHDR>() as u32);
                            if write_res == 0 {
                                in_flight.push(InFlightChunk {
                                    hdr,
                                    _data: pcm_data,
                                });
                            } else {
                                let _ = waveOutUnprepareHeader(hwo, &mut *hdr, std::mem::size_of::<WAVEHDR>() as u32);
                            }
                        }
                    }
                }

                Ok(PlaybackCommand::Stop) => {
                    if hwo != 0 {
                        unsafe {
                            let _ = waveOutReset(hwo);
                        }
                        for mut item in in_flight.drain(..) {
                            unsafe {
                                let _ = waveOutUnprepareHeader(hwo, &mut *item.hdr, std::mem::size_of::<WAVEHDR>() as u32);
                            }
                        }
                        unsafe {
                            let _ = waveOutClose(hwo);
                        }
                        hwo = 0;
                    }
                }

                Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
                    if hwo != 0 {
                        in_flight.retain_mut(|item| {
                            if (item.hdr.dwFlags & WHDR_DONE) != 0 {
                                unsafe {
                                    let _ = waveOutUnprepareHeader(hwo, &mut *item.hdr, std::mem::size_of::<WAVEHDR>() as u32);
                                }
                                false
                            } else {
                                true
                            }
                        });

                        if in_flight.is_empty() && last_chunk_time.elapsed() > Duration::from_secs(4) {
                            unsafe {
                                let _ = waveOutReset(hwo);
                                let _ = waveOutClose(hwo);
                            }
                            hwo = 0;
                        }
                    }
                }

                Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
                    break;
                }
            }
        }

        if hwo != 0 {
            unsafe {
                let _ = waveOutReset(hwo);
            }
            for mut item in in_flight.drain(..) {
                unsafe {
                    let _ = waveOutUnprepareHeader(hwo, &mut *item.hdr, std::mem::size_of::<WAVEHDR>() as u32);
                }
            }
            unsafe {
                let _ = waveOutClose(hwo);
            }
        }
    }
}

impl Drop for SystemAudioPlayback {
    fn drop(&mut self) {
        self.is_running.store(false, Ordering::Relaxed);
        self.stop();
    }
}
