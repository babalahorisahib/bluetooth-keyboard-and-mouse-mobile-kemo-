#![allow(non_snake_case, dead_code)]

use std::ffi::c_void;
use std::ptr;
use std::mem::size_of;

type HRESULT = i32;
const S_OK: HRESULT = 0;
const COINIT_MULTITHREADED: u32 = 0x0;
const CLSCTX_ALL: u32 = 23;
const eRender: u32 = 0;
const eConsole: u32 = 0;
const AUDCLNT_SHAREMODE_SHARED: u32 = 0;
const AUDCLNT_STREAMFLAGS_LOOPBACK: u32 = 0x00020000;
const AUDCLNT_BUFFERFLAGS_SILENT: u32 = 0x2;

#[repr(C)]
#[derive(Debug, Copy, Clone, PartialEq)]
struct GUID {
    Data1: u32,
    Data2: u16,
    Data3: u16,
    Data4: [u8; 8],
}

const CLSID_MMDeviceEnumerator: GUID = GUID {
    Data1: 0xBCDE0395, Data2: 0xE52F, Data3: 0x467C,
    Data4: [0x8E, 0x3D, 0xC4, 0x57, 0x92, 0x91, 0x69, 0x2E],
};

const IID_IMMDeviceEnumerator: GUID = GUID {
    Data1: 0xA95664D2, Data2: 0x9614, Data3: 0x4F35,
    Data4: [0xA7, 0x46, 0xDE, 0x8D, 0xB6, 0x36, 0x17, 0xE6],
};

const IID_IAudioClient: GUID = GUID {
    Data1: 0x1CB9AD4C, Data2: 0xDBFA, Data3: 0x4c32,
    Data4: [0xB1, 0x78, 0xC2, 0xF5, 0x68, 0xA7, 0x03, 0xB2],
};

const IID_IAudioCaptureClient: GUID = GUID {
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

fn main() {
    unsafe {
        let hr = CoInitializeEx(ptr::null_mut(), COINIT_MULTITHREADED);
        println!("CoInitializeEx: hr={:#X}", hr);

        let mut pEnumerator: *mut c_void = ptr::null_mut();
        let hr = CoCreateInstance(&CLSID_MMDeviceEnumerator, ptr::null_mut(), CLSCTX_ALL, &IID_IMMDeviceEnumerator, &mut pEnumerator);
        if hr != S_OK || pEnumerator.is_null() {
            println!("Failed to create MMDeviceEnumerator: hr={:#X}", hr);
            return;
        }
        println!("Created MMDeviceEnumerator: {:p}", pEnumerator);

        let vtbl_enum = *(pEnumerator as *mut *mut IMMDeviceEnumeratorVtbl);
        let mut pDevice: *mut c_void = ptr::null_mut();
        let hr = ((*vtbl_enum).GetDefaultAudioEndpoint)(pEnumerator, eRender, eConsole, &mut pDevice);
        if hr != S_OK || pDevice.is_null() {
            println!("Failed GetDefaultAudioEndpoint: hr={:#X}", hr);
            return;
        }
        println!("Got default audio endpoint: {:p}", pDevice);

        let vtbl_dev = *(pDevice as *mut *mut IMMDeviceVtbl);
        let mut pAudioClient: *mut c_void = ptr::null_mut();
        let hr = ((*vtbl_dev).Activate)(pDevice, &IID_IAudioClient, CLSCTX_ALL, ptr::null_mut(), &mut pAudioClient);
        if hr != S_OK || pAudioClient.is_null() {
            println!("Failed Activate IAudioClient: hr={:#X}", hr);
            return;
        }
        println!("Activated IAudioClient: {:p}", pAudioClient);

        let vtbl_client = *(pAudioClient as *mut *mut IAudioClientVtbl);
        let mut pMixFormat: *mut WAVEFORMATEX = ptr::null_mut();
        let hr = ((*vtbl_client).GetMixFormat)(pAudioClient, &mut pMixFormat);
        if hr != S_OK || pMixFormat.is_null() {
            println!("Failed GetMixFormat: hr={:#X}", hr);
            return;
        }

        let fmt = *pMixFormat;
        println!("Mix Format: tag={} channels={} sample_rate={} bits={} cbSize={}",
            fmt.wFormatTag, fmt.nChannels, fmt.nSamplesPerSec, fmt.wBitsPerSample, fmt.cbSize);

        // 100ms buffer (1,000,000 hns)
        let hr = ((*vtbl_client).Initialize)(pAudioClient, AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK, 1_000_000, 0, pMixFormat, ptr::null());
        if hr != S_OK {
            println!("Failed Initialize AudioClient in loopback mode: hr={:#X}", hr);
            return;
        }
        println!("Initialized AudioClient in LOOPBACK mode!");

        let mut pCaptureClient: *mut c_void = ptr::null_mut();
        let hr = ((*vtbl_client).GetService)(pAudioClient, &IID_IAudioCaptureClient, &mut pCaptureClient);
        if hr != S_OK || pCaptureClient.is_null() {
            println!("Failed GetService IAudioCaptureClient: hr={:#X}", hr);
            return;
        }
        println!("Got IAudioCaptureClient: {:p}", pCaptureClient);

        let vtbl_cap = *(pCaptureClient as *mut *mut IAudioCaptureClientVtbl);
        let hr = ((*vtbl_client).Start)(pAudioClient);
        println!("AudioClient started: hr={:#X}", hr);

        println!("Capturing 1 second of audio frames from Windows system output...");
        let start = std::time::Instant::now();
        let mut total_frames = 0u64;
        let mut packets = 0u32;

        while start.elapsed() < std::time::Duration::from_millis(1000) {
            let mut packet_size = 0u32;
            let hr = ((*vtbl_cap).GetNextPacketSize)(pCaptureClient, &mut packet_size);
            if hr == S_OK && packet_size > 0 {
                let mut pData: *mut u8 = ptr::null_mut();
                let mut num_frames = 0u32;
                let mut flags = 0u32;
                let hr = ((*vtbl_cap).GetBuffer)(pCaptureClient, &mut pData, &mut num_frames, &mut flags, ptr::null_mut(), ptr::null_mut());
                if hr == S_OK {
                    total_frames += num_frames as u64;
                    packets += 1;
                    let is_silent = (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0;
                    if packets % 10 == 0 {
                        println!("Captured packet #{}: frames={} silent={}", packets, num_frames, is_silent);
                    }
                    let _ = ((*vtbl_cap).ReleaseBuffer)(pCaptureClient, num_frames);
                }
            } else {
                std::thread::sleep(std::time::Duration::from_millis(5));
            }
        }

        println!("Done! Total packets: {}, Total frames: {}", packets, total_frames);
        let _ = ((*vtbl_client).Stop)(pAudioClient);
        CoTaskMemFree(pMixFormat as *mut c_void);
        CoUninitialize();
    }
}
