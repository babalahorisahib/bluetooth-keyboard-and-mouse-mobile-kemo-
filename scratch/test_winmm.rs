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

fn main() {
    println!("Testing winmm audio playback...");
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
    if res != 0 {
        eprintln!("waveOutOpen failed with error code: {}", res);
        return;
    }
    println!("waveOutOpen successful! Handle: {}", hwo);

    // Generate a 0.5s 440Hz sine wave
    let num_samples = (sample_rate / 2) as usize;
    let mut pcm: Vec<i16> = Vec::with_capacity(num_samples);
    for i in 0..num_samples {
        let t = (i as f32) / (sample_rate as f32);
        let val = (t * 440.0 * 2.0 * std::f32::consts::PI).sin();
        pcm.push((val * 16000.0) as i16);
    }

    let mut pcm_bytes: Vec<u8> = Vec::with_capacity(pcm.len() * 2);
    for s in &pcm {
        pcm_bytes.extend_from_slice(&s.to_le_bytes());
    }

    let mut hdr = WAVEHDR {
        lpData: pcm_bytes.as_mut_ptr(),
        dwBufferLength: pcm_bytes.len() as u32,
        dwBytesRecorded: 0,
        dwUser: 0,
        dwFlags: 0,
        dwLoops: 0,
        lpNext: std::ptr::null_mut(),
        reserved: 0,
    };

    unsafe {
        let prep_res = waveOutPrepareHeader(hwo, &mut hdr, std::mem::size_of::<WAVEHDR>() as u32);
        println!("waveOutPrepareHeader res: {}", prep_res);
        let write_res = waveOutWrite(hwo, &mut hdr, std::mem::size_of::<WAVEHDR>() as u32);
        println!("waveOutWrite res: {}", write_res);

        // Wait until done
        while (hdr.dwFlags & WHDR_DONE) == 0 {
            thread::sleep(Duration::from_millis(10));
        }

        let unprep_res = waveOutUnprepareHeader(hwo, &mut hdr, std::mem::size_of::<WAVEHDR>() as u32);
        println!("waveOutUnprepareHeader res: {}", unprep_res);
        let close_res = waveOutClose(hwo);
        println!("waveOutClose res: {}", close_res);
    }

    println!("Playback test completed successfully!");
}
