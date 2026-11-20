#![cfg(target_os = "windows")]
#![allow(non_snake_case, dead_code)]

use std::ffi::c_void;
use std::ptr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};
use tokio::sync::mpsc::Sender;

type HRESULT = i32;
const S_OK: HRESULT = 0;
const COINIT_MULTITHREADED: u32 = 0x0;
const CLSCTX_ALL: u32 = 23;
const E_RENDER: u32 = 0;
const E_CONSOLE: u32 = 0;
const AUDCLNT_SHAREMODE_SHARED: u32 = 0;
const AUDCLNT_STREAMFLAGS_LOOPBACK: u32 = 0x00020000;
const AUDCLNT_BUFFERFLAGS_SILENT: u32 = 0x2;
const AUDCLNT_E_DEVICE_INVALIDATED: HRESULT = 0x88890004_u32 as i32;

#[repr(C)]
#[derive(Debug, Copy, Clone, PartialEq)]
struct GUID {
    Data1: u32,
    Data2: u16,
    Data3: u16,
    Data4: [u8; 8],
}

const CLSID_MMDEVICE_ENUMERATOR: GUID = GUID {
    Data1: 0xBCDE0395, Data2: 0xE52F, Data3: 0x467C,
    Data4: [0x8E, 0x3D, 0xC4, 0x57, 0x92, 0x91, 0x69, 0x2E],
};

const IID_IMMDEVICE_ENUMERATOR: GUID = GUID {
    Data1: 0xA95664D2, Data2: 0x9614, Data3: 0x4F35,
    Data4: [0xA7, 0x46, 0xDE, 0x8D, 0xB6, 0x36, 0x17, 0xE6],
};

const IID_IAUDIO_CLIENT: GUID = GUID {
    Data1: 0x1CB9AD4C, Data2: 0xDBFA, Data3: 0x4c32,
    Data4: [0xB1, 0x78, 0xC2, 0xF5, 0x68, 0xA7, 0x03, 0xB2],
};

const IID_IAUDIO_CAPTURE_CLIENT: GUID = GUID {
    Data1: 0xC8ADBD64, Data2: 0xE71E, Data3: 0x48a0,
    Data4: [0xA4, 0xDE, 0x18, 0x5C, 0x39, 0x5C, 0xD3, 0x17],
};

#[repr(C)]
struct IUnknownVtbl {
    QueryInterface: unsafe extern "system" fn(this: *mut c_void, riid: *const GUID, ppvObject: *mut *mut c_void) -> HRESULT,
    AddRef: unsafe extern "system" fn(this: *mut c_void) -> u32,
    Release: unsafe extern "system" fn(this: *mut c_void) -> u32,
}

#[repr(C)]
struct IMMDeviceEnumeratorVtbl {
    base: IUnknownVtbl,
    EnumAudioEndpoints: unsafe extern "system" fn(this: *mut c_void, dataFlow: u32, dwStateMask: u32, ppDevices: *mut *mut c_void) -> HRESULT,
    GetDefaultAudioEndpoint: unsafe extern "system" fn(this: *mut c_void, dataFlow: u32, role: u32, ppEndpoint: *mut *mut c_void) -> HRESULT,
    GetDevice: unsafe extern "system" fn(this: *mut c_void, pwstrId: *const u16, ppDevice: *mut *mut c_void) -> HRESULT,
    RegisterEndpointNotificationCallback: unsafe extern "system" fn(this: *mut c_void, pClient: *mut c_void) -> HRESULT,
    UnregisterEndpointNotificationCallback: unsafe extern "system" fn(this: *mut c_void, pClient: *mut c_void) -> HRESULT,
}

#[repr(C)]
struct IMMDeviceVtbl {
    base: IUnknownVtbl,
    Activate: unsafe extern "system" fn(this: *mut c_void, iid: *const GUID, dwClsCtx: u32, pActivationParams: *mut c_void, ppInterface: *mut *mut c_void) -> HRESULT,
    OpenPropertyStore: unsafe extern "system" fn(this: *mut c_void, stgmAccess: u32, ppProperties: *mut *mut c_void) -> HRESULT,
    GetId: unsafe extern "system" fn(this: *mut c_void, ppstrId: *mut *mut u16) -> HRESULT,
    GetState: unsafe extern "system" fn(this: *mut c_void, pdwState: *mut u32) -> HRESULT,
}

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
struct IAudioClientVtbl {
    base: IUnknownVtbl,
    Initialize: unsafe extern "system" fn(this: *mut c_void, ShareMode: u32, StreamFlags: u32, hnsBufferDuration: i64, hnsPeriodicity: i64, pFormat: *const WAVEFORMATEX, AudioSessionGuid: *const GUID) -> HRESULT,
    GetBufferSize: unsafe extern "system" fn(this: *mut c_void, pNumBufferFrames: *mut u32) -> HRESULT,
    GetStreamLatency: unsafe extern "system" fn(this: *mut c_void, phnsLatency: *mut i64) -> HRESULT,
    GetCurrentPadding: unsafe extern "system" fn(this: *mut c_void, pNumPaddingFrames: *mut u32) -> HRESULT,
    IsFormatSupported: unsafe extern "system" fn(this: *mut c_void, ShareMode: u32, pFormat: *const WAVEFORMATEX, ppClosestMatch: *mut *mut WAVEFORMATEX) -> HRESULT,
    GetMixFormat: unsafe extern "system" fn(this: *mut c_void, ppDeviceFormat: *mut *mut WAVEFORMATEX) -> HRESULT,
    GetDevicePeriod: unsafe extern "system" fn(this: *mut c_void, phnsDefaultDevicePeriod: *mut i64, phnsMinimumDevicePeriod: *mut i64) -> HRESULT,
    Start: unsafe extern "system" fn(this: *mut c_void) -> HRESULT,
    Stop: unsafe extern "system" fn(this: *mut c_void) -> HRESULT,
    Reset: unsafe extern "system" fn(this: *mut c_void) -> HRESULT,
    SetEventHandle: unsafe extern "system" fn(this: *mut c_void, eventHandle: *mut c_void) -> HRESULT,
    GetService: unsafe extern "system" fn(this: *mut c_void, riid: *const GUID, ppv: *mut *mut c_void) -> HRESULT,
}

#[repr(C)]
struct IAudioCaptureClientVtbl {
    base: IUnknownVtbl,
    GetBuffer: unsafe extern "system" fn(this: *mut c_void, ppData: *mut *mut u8, pNumFramesToRead: *mut u32, pdwFlags: *mut u32, pu64DevicePosition: *mut u64, pu64QPCPosition: *mut u64) -> HRESULT,
    ReleaseBuffer: unsafe extern "system" fn(this: *mut c_void, NumFramesRead: u32) -> HRESULT,
    GetNextPacketSize: unsafe extern "system" fn(this: *mut c_void, pNumFramesInNextPacket: *mut u32) -> HRESULT,
}

#[link(name = "ole32")]
extern "system" {
    fn CoInitializeEx(pvReserved: *mut c_void, dwCoInit: u32) -> HRESULT;
    fn CoUninitialize();
    fn CoCreateInstance(rclsid: *const GUID, pUnkOuter: *mut c_void, dwClsContext: u32, riid: *const GUID, ppv: *mut *mut c_void) -> HRESULT;
    fn CoTaskMemFree(pv: *mut c_void);
}

pub struct SystemAudioCapture {
    is_running: Arc<AtomicBool>,
    thread_handle: Option<thread::JoinHandle<()>>,
}

impl SystemAudioCapture {
    pub fn new() -> Self {
        SystemAudioCapture {
            is_running: Arc::new(AtomicBool::new(false)),
            thread_handle: None,
        }
    }

    pub fn is_active(&self) -> bool {
        self.is_running.load(Ordering::Relaxed)
    }

    pub fn start(&mut self, audio_tx: Sender<Vec<u8>>) {
        if self.is_active() {
            return;
        }

        self.is_running.store(true, Ordering::SeqCst);
        let running_flag = Arc::clone(&self.is_running);

        let handle = thread::Builder::new()
            .name("kemo-audio-capture".into())
            .spawn(move || {
                unsafe {
                    let _ = CoInitializeEx(ptr::null_mut(), COINIT_MULTITHREADED);
                    Self::capture_loop(running_flag, audio_tx);
                    CoUninitialize();
                }
            })
            .ok();

        self.thread_handle = handle;
    }

    pub fn stop(&mut self) {
        self.is_running.store(false, Ordering::SeqCst);
        if let Some(h) = self.thread_handle.take() {
            let _ = h.join();
        }
    }

    unsafe fn capture_loop(running: Arc<AtomicBool>, audio_tx: Sender<Vec<u8>>) {
        let mut seq: u16 = 0;

        while running.load(Ordering::Relaxed) {
            let mut pEnumerator: *mut c_void = ptr::null_mut();
            let hr = CoCreateInstance(&CLSID_MMDEVICE_ENUMERATOR, ptr::null_mut(), CLSCTX_ALL, &IID_IMMDEVICE_ENUMERATOR, &mut pEnumerator);
            if hr != S_OK || pEnumerator.is_null() {
                thread::sleep(Duration::from_millis(500));
                continue;
            }

            let vtbl_enum = *(pEnumerator as *mut *mut IMMDeviceEnumeratorVtbl);
            let mut pDevice: *mut c_void = ptr::null_mut();
            let hr = ((*vtbl_enum).GetDefaultAudioEndpoint)(pEnumerator, E_RENDER, E_CONSOLE, &mut pDevice);
            if hr != S_OK || pDevice.is_null() {
                let release_enum = (*vtbl_enum).base.Release;
                release_enum(pEnumerator);
                thread::sleep(Duration::from_millis(500));
                continue;
            }

            let vtbl_dev = *(pDevice as *mut *mut IMMDeviceVtbl);
            let mut pAudioClient: *mut c_void = ptr::null_mut();
            let hr = ((*vtbl_dev).Activate)(pDevice, &IID_IAUDIO_CLIENT, CLSCTX_ALL, ptr::null_mut(), &mut pAudioClient);
            if hr != S_OK || pAudioClient.is_null() {
                let release_dev = (*vtbl_dev).base.Release;
                release_dev(pDevice);
                let release_enum = (*vtbl_enum).base.Release;
                release_enum(pEnumerator);
                thread::sleep(Duration::from_millis(500));
                continue;
            }

            let vtbl_client = *(pAudioClient as *mut *mut IAudioClientVtbl);
            let mut pMixFormat: *mut WAVEFORMATEX = ptr::null_mut();
            let hr = ((*vtbl_client).GetMixFormat)(pAudioClient, &mut pMixFormat);
            if hr != S_OK || pMixFormat.is_null() {
                let release_client = (*vtbl_client).base.Release;
                release_client(pAudioClient);
                let release_dev = (*vtbl_dev).base.Release;
                release_dev(pDevice);
                let release_enum = (*vtbl_enum).base.Release;
                release_enum(pEnumerator);
                thread::sleep(Duration::from_millis(500));
                continue;
            }

            let fmt = *pMixFormat;
            let sample_rate = fmt.nSamplesPerSec;
            let channels = fmt.nChannels.max(1) as usize;
            let bits = fmt.wBitsPerSample;
            let is_float = fmt.wBitsPerSample == 32;

            // 100ms internal WASAPI loopback buffer
            let hr = ((*vtbl_client).Initialize)(pAudioClient, AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK, 1_000_000, 0, pMixFormat, ptr::null());
            if hr != S_OK {
                CoTaskMemFree(pMixFormat as *mut c_void);
                let release_client = (*vtbl_client).base.Release;
                release_client(pAudioClient);
                let release_dev = (*vtbl_dev).base.Release;
                release_dev(pDevice);
                let release_enum = (*vtbl_enum).base.Release;
                release_enum(pEnumerator);
                thread::sleep(Duration::from_millis(500));
                continue;
            }

            let mut pCaptureClient: *mut c_void = ptr::null_mut();
            let hr = ((*vtbl_client).GetService)(pAudioClient, &IID_IAUDIO_CAPTURE_CLIENT, &mut pCaptureClient);
            if hr != S_OK || pCaptureClient.is_null() {
                CoTaskMemFree(pMixFormat as *mut c_void);
                let release_client = (*vtbl_client).base.Release;
                release_client(pAudioClient);
                let release_dev = (*vtbl_dev).base.Release;
                release_dev(pDevice);
                let release_enum = (*vtbl_enum).base.Release;
                release_enum(pEnumerator);
                thread::sleep(Duration::from_millis(500));
                continue;
            }

            let vtbl_cap = *(pCaptureClient as *mut *mut IAudioCaptureClientVtbl);
            let _ = ((*vtbl_client).Start)(pAudioClient);

            // Buffer ~20ms chunks of audio for transmission
            // e.g. at 48000Hz, 20ms is 960 frames. At 2 channels, 1920 samples = 3840 bytes.
            let chunk_frames_target = (sample_rate / 50).max(480) as usize; // ~20ms
            let mut pcm_accumulator: Vec<i16> = Vec::with_capacity(chunk_frames_target * channels);

            let mut last_capture_tick = Instant::now();

            while running.load(Ordering::Relaxed) {
                let mut packet_size = 0u32;
                let hr = ((*vtbl_cap).GetNextPacketSize)(pCaptureClient, &mut packet_size);

                if hr == AUDCLNT_E_DEVICE_INVALIDATED {
                    // Default audio device changed or unplugged
                    break;
                }

                if hr == S_OK && packet_size > 0 {
                    let mut pData: *mut u8 = ptr::null_mut();
                    let mut num_frames = 0u32;
                    let mut flags = 0u32;

                    let hr = ((*vtbl_cap).GetBuffer)(pCaptureClient, &mut pData, &mut num_frames, &mut flags, ptr::null_mut(), ptr::null_mut());
                    if hr == S_OK && num_frames > 0 {
                        let is_silent = (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0;
                        let total_samples = num_frames as usize * channels;

                        if is_silent || pData.is_null() {
                            pcm_accumulator.resize(pcm_accumulator.len() + total_samples, 0);
                        } else if is_float {
                            let float_slice = std::slice::from_raw_parts(pData as *const f32, total_samples);
                            for &f in float_slice {
                                let s = (f.clamp(-1.0, 1.0) * 32767.0) as i16;
                                pcm_accumulator.push(s);
                            }
                        } else if bits == 16 {
                            let i16_slice = std::slice::from_raw_parts(pData as *const i16, total_samples);
                            pcm_accumulator.extend_from_slice(i16_slice);
                        }

                        let _ = ((*vtbl_cap).ReleaseBuffer)(pCaptureClient, num_frames);
                        last_capture_tick = Instant::now();
                    }
                } else {
                    // When system is completely idle, WASAPI loopback does not pump packets.
                    // If idle for > 40ms, sleep briefly to prevent 100% CPU.
                    if last_capture_tick.elapsed() > Duration::from_millis(40) {
                        thread::sleep(Duration::from_millis(10));
                    } else {
                        thread::sleep(Duration::from_millis(3));
                    }
                }

                // If accumulator reached target chunk size, packetize and dispatch
                let samples_target = chunk_frames_target * channels;
                while pcm_accumulator.len() >= samples_target {
                    let chunk: Vec<i16> = pcm_accumulator.drain(..samples_target).collect();

                    // Build packet:
                    // [0..4]   Magic: b"KAUD"
                    // [4]      Version: 1
                    // [5]      Channels: channels as u8
                    // [6..10]  SampleRate: sample_rate as u32 (LE)
                    // [10..12] Sequence: seq (LE)
                    // [12..]   PCM16 samples (LE)
                    let pcm_bytes_len = chunk.len() * 2;
                    let mut packet = Vec::with_capacity(12 + pcm_bytes_len);
                    packet.extend_from_slice(b"KAUD");
                    packet.push(1); // Version 1
                    packet.push(channels as u8);
                    packet.extend_from_slice(&sample_rate.to_le_bytes());
                    packet.extend_from_slice(&seq.to_le_bytes());
                    seq = seq.wrapping_add(1);

                    for s in chunk {
                        packet.extend_from_slice(&s.to_le_bytes());
                    }

                    // Low-latency dispatch: try_send drops if buffer full, ensuring zero lag!
                    let _ = audio_tx.try_send(packet);
                }
            }

            // Cleanup this device session before re-looping or exiting
            let _ = ((*vtbl_client).Stop)(pAudioClient);
            let release_cap = (*vtbl_cap).base.Release;
            release_cap(pCaptureClient);
            CoTaskMemFree(pMixFormat as *mut c_void);
            let release_client = (*vtbl_client).base.Release;
            release_client(pAudioClient);
            let release_dev = (*vtbl_dev).base.Release;
            release_dev(pDevice);
            let release_enum = (*vtbl_enum).base.Release;
            release_enum(pEnumerator);

            thread::sleep(Duration::from_millis(200));
        }
    }
}

impl Drop for SystemAudioCapture {
    fn drop(&mut self) {
        self.stop();
    }
}
