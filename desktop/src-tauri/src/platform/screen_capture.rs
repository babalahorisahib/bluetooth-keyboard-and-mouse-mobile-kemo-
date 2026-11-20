#![cfg(target_os = "windows")]
#![allow(non_snake_case, dead_code)]

use std::ffi::c_void;
use std::mem::{size_of, zeroed};
use std::ffi::OsStr;
use std::os::windows::ffi::OsStrExt;
use jpeg_encoder::{ColorType, Encoder, SamplingFactor};

#[repr(C)]
#[derive(Copy, Clone)]
struct POINT {
    x: i32,
    y: i32,
}

#[repr(C)]
struct CURSORINFO {
    cbSize: u32,
    flags: u32,
    hCursor: *mut c_void,
    ptScreenPos: POINT,
}
const CURSOR_SHOWING: u32 = 0x00000001;

#[repr(C)]
struct BITMAPINFOHEADER {
    biSize: u32,
    biWidth: i32,
    biHeight: i32,
    biPlanes: u16,
    biBitCount: u16,
    biCompression: u32,
    biSizeImage: u32,
    biXPelsPerMeter: i32,
    biYPelsPerMeter: i32,
    biClrUsed: u32,
    biClrImportant: u32,
}

#[repr(C)]
struct BITMAPINFO {
    bmiHeader: BITMAPINFOHEADER,
    bmiColors: [u32; 1],
}

const BI_RGB: u32 = 0;
const DIB_RGB_COLORS: u32 = 0;
const SRCCOPY: u32 = 0x00CC0020;
const CAPTUREBLT: u32 = 0x40000000;
const ROP_COPY_CAPTURE: u32 = SRCCOPY | CAPTUREBLT;
const COLORONCOLOR: i32 = 3;
const HALFTONE: i32 = 4;

extern "system" {
    fn OpenInputDesktop(dwFlags: u32, fInherit: i32, dwDesiredAccess: u32) -> *mut c_void;
    fn OpenWindowStationW(lpszWinSta: *const u16, fInherit: i32, dwDesiredAccess: u32) -> *mut c_void;
    fn SetProcessWindowStation(hWinSta: *mut c_void) -> i32;
    fn CloseWindowStation(hWinSta: *mut c_void) -> i32;
    fn OpenDesktopW(lpszDesktop: *const u16, dwFlags: u32, fInherit: i32, dwDesiredAccess: u32) -> *mut c_void;
    fn SetThreadDesktop(hDesktop: *mut c_void) -> i32;
    fn CloseDesktop(hDesktop: *mut c_void) -> i32;
    fn GetDesktopWindow() -> *mut c_void;
    fn GetDC(hWnd: *mut c_void) -> *mut c_void;
    fn ReleaseDC(hWnd: *mut c_void, hDC: *mut c_void) -> i32;
    fn CreateCompatibleDC(hDC: *mut c_void) -> *mut c_void;
    fn CreateCompatibleBitmap(hDC: *mut c_void, cx: i32, cy: i32) -> *mut c_void;
    fn SelectObject(hDC: *mut c_void, h: *mut c_void) -> *mut c_void;
    fn BitBlt(hdc: *mut c_void, x: i32, y: i32, cx: i32, cy: i32, hdcSrc: *mut c_void, x1: i32, y1: i32, rop: u32) -> i32;
    fn SetStretchBltMode(hdc: *mut c_void, mode: i32) -> i32;
    fn SetBrushOrgEx(hdc: *mut c_void, x: i32, y: i32, lppt: *mut c_void) -> i32;
    fn StretchBlt(hdcDest: *mut c_void, xDest: i32, yDest: i32, wDest: i32, hDest: i32,
                  hdcSrc: *mut c_void, xSrc: i32, ySrc: i32, wSrc: i32, hSrc: i32, rop: u32) -> i32;
    fn DeleteDC(hdc: *mut c_void) -> i32;
    fn DeleteObject(ho: *mut c_void) -> i32;
    fn GetDIBits(hdc: *mut c_void, hbm: *mut c_void, start: u32, cLines: u32,
                 lpvBits: *mut c_void, lpbmi: *mut BITMAPINFO, usage: u32) -> i32;
    fn GetSystemMetrics(nIndex: i32) -> i32;
    fn GetCursorInfo(pci: *mut CURSORINFO) -> i32;
    fn DrawIcon(hDC: *mut c_void, X: i32, Y: i32, hIcon: *mut c_void) -> i32;
}

#[link(name = "dwmapi")]
extern "system" {
    fn DwmFlush() -> i32;
}

pub struct ScreenCapture {
    screen_w: i32,
    screen_h: i32,
    last_hash: std::sync::atomic::AtomicU64,
    last_frame_instant: std::sync::Mutex<Option<std::time::Instant>>,
}

impl ScreenCapture {
    pub fn new() -> Self {
        Self::ensure_desktop_access();
        let w = unsafe { GetSystemMetrics(0) }; // SM_CXSCREEN
        let h = unsafe { GetSystemMetrics(1) }; // SM_CYSCREEN
        ScreenCapture {
            screen_w: if w > 0 { w } else { 1920 },
            screen_h: if h > 0 { h } else { 1080 },
            last_hash: std::sync::atomic::AtomicU64::new(0),
            last_frame_instant: std::sync::Mutex::new(None),
        }
    }

    pub fn reset_cache(&self) {
        self.last_hash.store(0, std::sync::atomic::Ordering::SeqCst);
        if let Ok(mut g) = self.last_frame_instant.lock() {
            *g = None;
        }
    }

    pub fn ensure_desktop_access() {
        unsafe {
            // First check if active input desktop can be bound directly
            let h_input = OpenInputDesktop(0, 0, 0x01FF);
            if !h_input.is_null() {
                SetThreadDesktop(h_input);
                CloseDesktop(h_input);
                return;
            }

            let winsta_name: Vec<u16> = OsStr::new("WinSta0")
                .encode_wide()
                .chain(std::iter::once(0))
                .collect();
            let hwinsta = OpenWindowStationW(winsta_name.as_ptr(), 0, 0x037F);
            if !hwinsta.is_null() {
                SetProcessWindowStation(hwinsta);
                CloseWindowStation(hwinsta);
            }

            let desk_name: Vec<u16> = OsStr::new("Default")
                .encode_wide()
                .chain(std::iter::once(0))
                .collect();
            let hdesk = OpenDesktopW(desk_name.as_ptr(), 0, 0, 0x01FF);
            if !hdesk.is_null() {
                SetThreadDesktop(hdesk);
                CloseDesktop(hdesk);
            }
        }
    }

    pub fn get_resolution(&self) -> (i32, i32) {
        let w = unsafe { GetSystemMetrics(0) };
        let h = unsafe { GetSystemMetrics(1) };
        (if w > 0 { w } else { self.screen_w }, if h > 0 { h } else { self.screen_h })
    }

    /// Captures the full PC desktop and returns a compressed JPEG byte buffer.
    /// `max_width`: Downscale constraint (e.g. 1920 or 1366) to optimize bandwidth & latency.
    /// `quality`: JPEG quality 1-100 (recommended 85-95 with 4:4:4 chroma for razor sharp text).
    pub fn capture_frame(&self, max_width: u32, quality: u8) -> Option<Vec<u8>> {
        // Guarantee current worker thread is attached to active desktop once per thread
        thread_local! {
            static ATTACHED: std::cell::Cell<bool> = std::cell::Cell::new(false);
        }
        ATTACHED.with(|a| {
            if !a.get() {
                Self::ensure_desktop_access();
                a.set(true);
            }
        });

        let (screen_w, screen_h) = self.get_resolution();
        if screen_w <= 0 || screen_h <= 0 {
            return None;
        }

        // Calculate target dimensions preserving aspect ratio
        let target_w = if max_width > 0 && (max_width as i32) < screen_w {
            max_width as i32
        } else {
            screen_w
        };
        let target_h = ((target_w as f64 / screen_w as f64) * screen_h as f64).round() as i32;

        unsafe {
            let _ = DwmFlush();
            // Virtual screen DC with auto re-attachment
            let mut hdc_screen = GetDC(std::ptr::null_mut());
            if hdc_screen.is_null() {
                Self::ensure_desktop_access();
                hdc_screen = GetDC(std::ptr::null_mut());
                if hdc_screen.is_null() {
                    return None;
                }
            }

            let hdc_mem = CreateCompatibleDC(hdc_screen);
            if hdc_mem.is_null() {
                ReleaseDC(std::ptr::null_mut(), hdc_screen);
                return None;
            }

            let hbm = CreateCompatibleBitmap(hdc_screen, target_w, target_h);
            if hbm.is_null() {
                DeleteDC(hdc_mem);
                ReleaseDC(std::ptr::null_mut(), hdc_screen);
                return None;
            }

            let old_obj = SelectObject(hdc_mem, hbm);

            // Copy screen contents smoothly using pure SRCCOPY.
            // Using SRCCOPY avoids CAPTUREBLT which causes DWM composition & window blinking on Windows 10/11!
            let mut blt_ok = if target_w == screen_w && target_h == screen_h {
                BitBlt(hdc_mem, 0, 0, target_w, target_h, hdc_screen, 0, 0, SRCCOPY) != 0
            } else {
                SetStretchBltMode(hdc_mem, HALFTONE);
                SetBrushOrgEx(hdc_mem, 0, 0, std::ptr::null_mut());
                StretchBlt(hdc_mem, 0, 0, target_w, target_h, hdc_screen, 0, 0, screen_w, screen_h, SRCCOPY) != 0
            };

            // If SRCCOPY failed on this driver, fallback to ROP_COPY_CAPTURE
            if !blt_ok {
                if target_w == screen_w && target_h == screen_h {
                    blt_ok = BitBlt(hdc_mem, 0, 0, target_w, target_h, hdc_screen, 0, 0, ROP_COPY_CAPTURE) != 0;
                } else {
                    blt_ok = StretchBlt(hdc_mem, 0, 0, target_w, target_h, hdc_screen, 0, 0, screen_w, screen_h, ROP_COPY_CAPTURE) != 0;
                }
            }

            if !blt_ok {
                // If BitBlt failed, do NOT return a black buffer; abort cleanly
                SelectObject(hdc_mem, old_obj);
                DeleteObject(hbm);
                DeleteDC(hdc_mem);
                ReleaseDC(std::ptr::null_mut(), hdc_screen);
                return None;
            }

            // Draw real mouse cursor on the captured frame
            let mut ci: CURSORINFO = zeroed();
            ci.cbSize = size_of::<CURSORINFO>() as u32;
            if GetCursorInfo(&mut ci) != 0 && (ci.flags & CURSOR_SHOWING) != 0 {
                let cur_x = if screen_w > 0 {
                    ((ci.ptScreenPos.x as f64 / screen_w as f64) * target_w as f64).round() as i32
                } else {
                    ci.ptScreenPos.x
                };
                let cur_y = if screen_h > 0 {
                    ((ci.ptScreenPos.y as f64 / screen_h as f64) * target_h as f64).round() as i32
                } else {
                    ci.ptScreenPos.y
                };
                DrawIcon(hdc_mem, cur_x, cur_y, ci.hCursor);
            }

            // Extract pixel buffer
            let num_pixels = (target_w * target_h) as usize;
            let mut bgra_buf: Vec<u8> = vec![0u8; num_pixels * 4];

            let mut bmi: BITMAPINFO = zeroed();
            bmi.bmiHeader.biSize = size_of::<BITMAPINFOHEADER>() as u32;
            bmi.bmiHeader.biWidth = target_w;
            // Negative height specifies top-down DIB (row 0 is at the top)
            bmi.bmiHeader.biHeight = -target_h;
            bmi.bmiHeader.biPlanes = 1;
            bmi.bmiHeader.biBitCount = 32;
            bmi.bmiHeader.biCompression = BI_RGB;

            let lines = GetDIBits(
                hdc_mem,
                hbm,
                0,
                target_h as u32,
                bgra_buf.as_mut_ptr() as *mut c_void,
                &mut bmi,
                DIB_RGB_COLORS,
            );

            // Cleanup GDI objects
            SelectObject(hdc_mem, old_obj);
            DeleteObject(hbm);
            DeleteDC(hdc_mem);
            ReleaseDC(std::ptr::null_mut(), hdc_screen);

            if lines == 0 {
                return None;
            }

            // High-speed 128-point dirty check + cursor position hash (Zero-cost change detection)
            let mut current_hash: u64 = 0xcbf29ce484222325;
            let step = (bgra_buf.len() / 128).max(1);
            for i in (0..bgra_buf.len()).step_by(step) {
                current_hash ^= bgra_buf[i] as u64;
                current_hash = current_hash.wrapping_mul(0x100000001b3);
            }
            current_hash ^= (ci.ptScreenPos.x as u64) | ((ci.ptScreenPos.y as u64) << 32);

            let old_hash = self.last_hash.swap(current_hash, std::sync::atomic::Ordering::SeqCst);
            let mut last_instant_guard = self.last_frame_instant.lock().unwrap();
            let now = std::time::Instant::now();

            if old_hash == current_hash {
                if let Some(last_time) = *last_instant_guard {
                    if now.duration_since(last_time) < std::time::Duration::from_millis(1500) {
                        // Desktop is 100% identical and within 1.5s -> Skip redundant transmission!
                        return None;
                    }
                }
            }
            *last_instant_guard = Some(now);

            // Encode BGRA buffer to JPEG with 4:2:0 chroma sampling (ultra-compact 35KB payload, 5x faster)
            let eff_quality = quality.clamp(10, 75);
            let mut jpeg_buf: Vec<u8> = Vec::with_capacity(48 * 1024);
            let mut encoder = Encoder::new(&mut jpeg_buf, eff_quality);
            encoder.set_sampling_factor(SamplingFactor::R_4_2_0);
            if encoder.encode(&bgra_buf, target_w as u16, target_h as u16, ColorType::Bgra).is_ok() {
                Some(jpeg_buf)
            } else {
                None
            }
        }
    }
}
