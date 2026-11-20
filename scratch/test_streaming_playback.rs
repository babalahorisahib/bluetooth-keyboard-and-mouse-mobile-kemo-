#![cfg(target_os = "windows")]

use std::ffi::c_void;
use std::thread;
use std::time::Duration;

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

struct InFlight {
    hdr: Box<WAVEHDR>,
    _data: Vec<u8>,
}

fn main() {
    println!("Testing continuous streaming playback with ring buffers...");
    let sample_rate = 16000u32;
    let channels = 1u16;
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

    let mut hwo: usize = 0;
    let res = unsafe { waveOutOpen(&mut hwo, WAVE_MAPPER, &wfx, 0, 0, 0) };
    assert_eq!(res, 0);

    let mut in_flight: Vec<InFlight> = Vec::new();

    // Stream 20 chunks of 50ms each (1 second total audio)
    // 50ms at 16kHz = 800 samples = 1600 bytes
    let chunk_samples = 800;
    for chunk_idx in 0..20 {
        // Clean up done buffers
        in_flight.retain_mut(|item| {
            if (item.hdr.dwFlags & WHDR_DONE) != 0 {
                unsafe {
                    waveOutUnprepareHeader(hwo, &mut *item.hdr, std::mem::size_of::<WAVEHDR>() as u32);
                }
                false
            } else {
                true
            }
        });

        // Synthesize 50ms sine wave (tone changes over chunks)
        let freq = 300.0 + (chunk_idx as f32) * 20.0;
        let mut pcm_bytes = Vec::with_capacity(chunk_samples * 2);
        for i in 0..chunk_samples {
            let t = (i as f32) / (sample_rate as f32);
            let s = ((t * freq * 2.0 * std::f32::consts::PI).sin() * 12000.0) as i16;
            pcm_bytes.extend_from_slice(&s.to_le_bytes());
        }

        let mut hdr = Box::new(WAVEHDR {
            lpData: pcm_bytes.as_mut_ptr(),
            dwBufferLength: pcm_bytes.len() as u32,
            dwBytesRecorded: 0,
            dwUser: 0,
            dwFlags: 0,
            dwLoops: 0,
            lpNext: std::ptr::null_mut(),
            reserved: 0,
        });

        unsafe {
            let prep = waveOutPrepareHeader(hwo, &mut *hdr, std::mem::size_of::<WAVEHDR>() as u32);
            assert_eq!(prep, 0);
            let write = waveOutWrite(hwo, &mut *hdr, std::mem::size_of::<WAVEHDR>() as u32);
            assert_eq!(write, 0);
        }

        in_flight.push(InFlight {
            hdr,
            _data: pcm_bytes,
        });

        thread::sleep(Duration::from_millis(48));
    }

    // Wait for remaining buffers
    while !in_flight.is_empty() {
        in_flight.retain_mut(|item| {
            if (item.hdr.dwFlags & WHDR_DONE) != 0 {
                unsafe {
                    waveOutUnprepareHeader(hwo, &mut *item.hdr, std::mem::size_of::<WAVEHDR>() as u32);
                }
                false
            } else {
                true
            }
        });
        thread::sleep(Duration::from_millis(10));
    }

    unsafe {
        waveOutReset(hwo);
        waveOutClose(hwo);
    }

    println!("Continuous streaming test passed perfectly!");
}
