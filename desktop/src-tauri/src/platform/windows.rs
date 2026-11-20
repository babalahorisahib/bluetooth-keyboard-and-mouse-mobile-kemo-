#![cfg(target_os = "windows")]
#![allow(non_snake_case, dead_code)]

use std::ffi::c_void;
use std::ffi::OsStr;
use std::mem::{size_of, zeroed};
use std::os::windows::ffi::OsStrExt;

#[repr(C)]
#[derive(Copy, Clone)]
struct POINT {
    x: i32,
    y: i32,
}

#[repr(C)]
#[derive(Copy, Clone)]
struct MOUSEINPUT {
    dx: i32,
    dy: i32,
    mouseData: u32,
    dwFlags: u32,
    time: u32,
    dwExtraInfo: usize,
}

#[repr(C)]
#[derive(Copy, Clone)]
struct KEYBDINPUT {
    wVk: u16,
    wScan: u16,
    dwFlags: u32,
    time: u32,
    dwExtraInfo: usize,
}

#[repr(C)]
#[derive(Copy, Clone)]
struct HARDWAREINPUT {
    uMsg: u32,
    wParamL: u16,
    wParamH: u16,
}

#[repr(C)]
#[derive(Copy, Clone)]
union INPUT_UNION {
    mi: MOUSEINPUT,
    ki: KEYBDINPUT,
    hi: HARDWAREINPUT,
}

#[repr(C)]
#[derive(Copy, Clone)]
struct INPUT {
    r#type: u32,
    u: INPUT_UNION,
}

const INPUT_MOUSE: u32 = 0;
const INPUT_KEYBOARD: u32 = 1;

const MOUSEEVENTF_MOVE: u32 = 0x0001;
const MOUSEEVENTF_LEFTDOWN: u32 = 0x0002;
const MOUSEEVENTF_LEFTUP: u32 = 0x0004;
const MOUSEEVENTF_RIGHTDOWN: u32 = 0x0008;
const MOUSEEVENTF_RIGHTUP: u32 = 0x0010;
const MOUSEEVENTF_MIDDLEDOWN: u32 = 0x0020;
const MOUSEEVENTF_MIDDLEUP: u32 = 0x0040;
const MOUSEEVENTF_WHEEL: u32 = 0x0800;
const MOUSEEVENTF_HWHEEL: u32 = 0x1000;
const MOUSEEVENTF_ABSOLUTE: u32 = 0x8000;

const KEYEVENTF_EXTENDEDKEY: u32 = 0x0001;
const KEYEVENTF_KEYUP: u32 = 0x0002;
const KEYEVENTF_UNICODE: u32 = 0x0004;

const VK_BACK: u16 = 0x08;
const VK_TAB: u16 = 0x09;
const VK_RETURN: u16 = 0x0D;
const VK_SHIFT: u16 = 0x10;
const VK_CONTROL: u16 = 0x11;
const VK_MENU: u16 = 0x12; // Alt
const VK_ESCAPE: u16 = 0x1B;
const VK_SPACE: u16 = 0x20;
const VK_PRIOR: u16 = 0x21; // PageUp
const VK_NEXT: u16 = 0x22;  // PageDown
const VK_END: u16 = 0x23;
const VK_HOME: u16 = 0x24;
const VK_LEFT: u16 = 0x25;
const VK_UP: u16 = 0x26;
const VK_RIGHT: u16 = 0x27;
const VK_DOWN: u16 = 0x28;
const VK_DELETE: u16 = 0x2E;
const VK_LWIN: u16 = 0x5B;
const VK_VOLUME_MUTE: u16 = 0xAD;
const VK_VOLUME_DOWN: u16 = 0xAE;
const VK_VOLUME_UP: u16 = 0xAF;

extern "system" {
    fn OpenInputDesktop(dwFlags: u32, fInherit: i32, dwDesiredAccess: u32) -> *mut c_void;
    fn OpenWindowStationW(lpszWinSta: *const u16, fInherit: i32, dwDesiredAccess: u32) -> *mut c_void;
    fn SetProcessWindowStation(hWinSta: *mut c_void) -> i32;
    fn CloseWindowStation(hWinSta: *mut c_void) -> i32;
    fn SetThreadDesktop(hDesktop: *mut c_void) -> i32;
    fn SendInput(cInputs: u32, pInputs: *mut INPUT, cbSize: i32) -> u32;
    fn GetCursorPos(lpPoint: *mut POINT) -> i32;
    fn SetCursorPos(X: i32, Y: i32) -> i32;
    fn GetSystemMetrics(nIndex: i32) -> i32;
    fn MapVirtualKeyW(uCode: u32, uMapType: u32) -> u32;
    fn mouse_event(dwFlags: u32, dx: i32, dy: i32, dwData: u32, dwExtraInfo: usize);
    fn keybd_event(bVk: u8, bScan: u8, dwFlags: u32, dwExtraInfo: usize);
    fn GetLastError() -> u32;
}

thread_local! {
    static DESKTOP_BOUND: std::cell::Cell<bool> = std::cell::Cell::new(false);
}

pub fn ensure_desktop_access() {
    DESKTOP_BOUND.with(|bound| {
        if !bound.get() {
            unsafe {
                let winsta_name: Vec<u16> = OsStr::new("WinSta0")
                    .encode_wide()
                    .chain(std::iter::once(0))
                    .collect();
                let hwinsta = OpenWindowStationW(winsta_name.as_ptr(), 0, 0x037F);
                if !hwinsta.is_null() {
                    SetProcessWindowStation(hwinsta);
                    CloseWindowStation(hwinsta);
                }

                let h_input = OpenInputDesktop(0, 0, 0x01FF);
                if !h_input.is_null() {
                    if SetThreadDesktop(h_input) != 0 {
                        bound.set(true);
                    }
                }
            }
        }
    });
}

fn safe_send_input(inputs: &mut [INPUT]) -> u32 {
    if inputs.is_empty() {
        return 0;
    }
    ensure_desktop_access();
    let count = inputs.len() as u32;
    let res = unsafe { SendInput(count, inputs.as_mut_ptr(), size_of::<INPUT>() as i32) };
    if res == count {
        return res;
    }

    // If SendInput failed, force re-attachment to input desktop and retry
    DESKTOP_BOUND.with(|b| b.set(false));
    unsafe {
        let h_input = OpenInputDesktop(0, 0, 0x01FF);
        if !h_input.is_null() {
            SetThreadDesktop(h_input);
        }
        let retry_res = SendInput(count, inputs.as_mut_ptr(), size_of::<INPUT>() as i32);
        if retry_res == count {
            return retry_res;
        }

        // Dual fallback using driver-level mouse_event and keybd_event (guaranteed execution)
        for inp in inputs.iter() {
            if inp.r#type == INPUT_MOUSE {
                mouse_event(
                    inp.u.mi.dwFlags,
                    inp.u.mi.dx,
                    inp.u.mi.dy,
                    inp.u.mi.mouseData,
                    inp.u.mi.dwExtraInfo,
                );
            } else if inp.r#type == INPUT_KEYBOARD {
                keybd_event(
                    inp.u.ki.wVk as u8,
                    inp.u.ki.wScan as u8,
                    inp.u.ki.dwFlags,
                    inp.u.ki.dwExtraInfo,
                );
            }
        }
        count
    }
}

fn safe_set_cursor_pos(x: i32, y: i32) {
    ensure_desktop_access();
    let res = unsafe { SetCursorPos(x, y) };
    if res == 0 {
        DESKTOP_BOUND.with(|b| b.set(false));
        unsafe {
            let h_input = OpenInputDesktop(0, 0, 0x01FF);
            if !h_input.is_null() {
                SetThreadDesktop(h_input);
            }
            SetCursorPos(x, y);
        }
    }
}

pub struct WindowsDriver {
    subpixel: std::sync::Mutex<(f64, f64)>,
}

impl WindowsDriver {
    pub fn new() -> Self {
        ensure_desktop_access();
        WindowsDriver {
            subpixel: std::sync::Mutex::new((0.0, 0.0)),
        }
    }

    /// Absolute touch event on screen (acting like a touchscreen digitizer)
    pub fn touch_event(&self, action: &str, norm_x: f64, norm_y: f64) {
        if let Ok(mut sub) = self.subpixel.lock() {
            *sub = (0.0, 0.0);
        }
        let screen_w = unsafe { GetSystemMetrics(0) }; // SM_CXSCREEN
        let screen_h = unsafe { GetSystemMetrics(1) }; // SM_CYSCREEN
        let w = if screen_w > 0 { screen_w } else { 1920 };
        let h = if screen_h > 0 { screen_h } else { 1080 };

        let target_x = (norm_x.clamp(0.0, 1.0) * (w - 1) as f64).round() as i32;
        let target_y = (norm_y.clamp(0.0, 1.0) * (h - 1) as f64).round() as i32;

        let norm_x_u32 = ((target_x as f64 / (w - 1).max(1) as f64) * 65535.0).round() as i32;
        let norm_y_u32 = ((target_y as f64 / (h - 1).max(1) as f64) * 65535.0).round() as i32;

        let mut move_input: INPUT = unsafe { zeroed() };
        move_input.r#type = INPUT_MOUSE;
        move_input.u.mi.dx = norm_x_u32;
        move_input.u.mi.dy = norm_y_u32;
        move_input.u.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE;

        safe_send_input(&mut [move_input]);
        safe_set_cursor_pos(target_x, target_y);

        match action {
            "tap" => {
                self.mouse_click("left", "click");
            }
            "double_tap" => {
                // First tap already sent click #1. Ensure cursor position is locked and send click #2
                safe_set_cursor_pos(target_x, target_y);
                self.mouse_click("left", "click");
            }
            "right_click" => {
                self.mouse_click("right", "click");
            }
            "down" => {
                self.mouse_click("left", "down");
            }
            "move" => {
                // Cursor already moved above
            }
            "up" => {
                self.mouse_click("left", "up");
            }
            _ => {}
        }
    }

    /// Move mouse relative by dx, dy with true sub-pixel accumulator precision
    pub fn mouse_move(&self, dx: f64, dy: f64) {
        let (idx, idy) = {
            let mut sub = self.subpixel.lock().unwrap();
            let total_x = sub.0 + dx;
            let total_y = sub.1 + dy;
            let ix = total_x.trunc() as i32;
            let iy = total_y.trunc() as i32;
            sub.0 = total_x - (ix as f64);
            sub.1 = total_y - (iy as f64);
            (ix, iy)
        };

        if idx == 0 && idy == 0 {
            return;
        }
        let mut input: INPUT = unsafe { zeroed() };
        input.r#type = INPUT_MOUSE;
        input.u.mi = MOUSEINPUT {
            dx: idx,
            dy: idy,
            mouseData: 0,
            dwFlags: MOUSEEVENTF_MOVE,
            time: 0,
            dwExtraInfo: 0,
        };
        safe_send_input(&mut [input]);
    }

    /// Mouse click (left, right, middle) with actions (click, double, down, up)
    pub fn mouse_click(&self, button: &str, action: &str) {
        let (down_flag, up_flag) = match button {
            "right" => (MOUSEEVENTF_RIGHTDOWN, MOUSEEVENTF_RIGHTUP),
            "middle" => (MOUSEEVENTF_MIDDLEDOWN, MOUSEEVENTF_MIDDLEUP),
            _ => (MOUSEEVENTF_LEFTDOWN, MOUSEEVENTF_LEFTUP),
        };

        match action {
            "down" => {
                let mut input: INPUT = unsafe { zeroed() };
                input.r#type = INPUT_MOUSE;
                input.u.mi.dwFlags = down_flag;
                safe_send_input(&mut [input]);
            }
            "up" => {
                let mut input: INPUT = unsafe { zeroed() };
                input.r#type = INPUT_MOUSE;
                input.u.mi.dwFlags = up_flag;
                safe_send_input(&mut [input]);
            }
            "double" => {
                let mut down1: INPUT = unsafe { zeroed() };
                down1.r#type = INPUT_MOUSE;
                down1.u.mi.dwFlags = down_flag;
                let mut up1: INPUT = unsafe { zeroed() };
                up1.r#type = INPUT_MOUSE;
                up1.u.mi.dwFlags = up_flag;

                let mut down2: INPUT = unsafe { zeroed() };
                down2.r#type = INPUT_MOUSE;
                down2.u.mi.dwFlags = down_flag;
                let mut up2: INPUT = unsafe { zeroed() };
                up2.r#type = INPUT_MOUSE;
                up2.u.mi.dwFlags = up_flag;

                safe_send_input(&mut [down1]);
                std::thread::sleep(std::time::Duration::from_millis(15));
                safe_send_input(&mut [up1]);
                std::thread::sleep(std::time::Duration::from_millis(40));
                safe_send_input(&mut [down2]);
                std::thread::sleep(std::time::Duration::from_millis(15));
                safe_send_input(&mut [up2]);
            }
            _ => { // default: single click
                let mut down: INPUT = unsafe { zeroed() };
                down.r#type = INPUT_MOUSE;
                down.u.mi.dwFlags = down_flag;
                let mut up: INPUT = unsafe { zeroed() };
                up.r#type = INPUT_MOUSE;
                up.u.mi.dwFlags = up_flag;

                safe_send_input(&mut [down]);
                std::thread::sleep(std::time::Duration::from_millis(15));
                safe_send_input(&mut [up]);
            }
        }
    }

    /// Scroll vertically and horizontally
    pub fn mouse_scroll(&self, dx: f64, dy: f64) {
        if dy.abs() > 0.001 {
            let mut input: INPUT = unsafe { zeroed() };
            input.r#type = INPUT_MOUSE;
            input.u.mi = MOUSEINPUT {
                dx: 0,
                dy: 0,
                mouseData: dy.round() as i32 as u32,
                dwFlags: MOUSEEVENTF_WHEEL,
                time: 0,
                dwExtraInfo: 0,
            };
            safe_send_input(&mut [input]);
        }

        if dx.abs() > 0.001 {
            let mut input: INPUT = unsafe { zeroed() };
            input.r#type = INPUT_MOUSE;
            input.u.mi = MOUSEINPUT {
                dx: 0,
                dy: 0,
                mouseData: dx.round() as i32 as u32,
                dwFlags: MOUSEEVENTF_HWHEEL,
                time: 0,
                dwExtraInfo: 0,
            };
            safe_send_input(&mut [input]);
        }
    }

    /// Injects Unicode text (full support for Urdu, English, emojis, etc.)
    pub fn send_text(&self, text: &str) {
        let utf16_units: Vec<u16> = text.encode_utf16().collect();
        let mut inputs: Vec<INPUT> = Vec::with_capacity(utf16_units.len() * 2);

        for &code_unit in &utf16_units {
            // Key down
            let mut down: INPUT = unsafe { zeroed() };
            down.r#type = INPUT_KEYBOARD;
            down.u.ki = KEYBDINPUT {
                wVk: 0,
                wScan: code_unit,
                dwFlags: KEYEVENTF_UNICODE,
                time: 0,
                dwExtraInfo: 0,
            };
            inputs.push(down);

            // Key up
            let mut up: INPUT = unsafe { zeroed() };
            up.r#type = INPUT_KEYBOARD;
            up.u.ki = KEYBDINPUT {
                wVk: 0,
                wScan: code_unit,
                dwFlags: KEYEVENTF_UNICODE | KEYEVENTF_KEYUP,
                time: 0,
                dwExtraInfo: 0,
            };
            inputs.push(up);
        }

        if !inputs.is_empty() {
            safe_send_input(&mut inputs);
        }
    }

    /// Injects standard keyboard key events with hardware scan codes and proper modifiers
    pub fn send_key(&self, key: &str, action: &str, modifiers: &[String]) {
        let clean_key = key.trim().to_lowercase();
        let (vk, is_extended, default_scan) = match clean_key.as_str() {
            "backspace" | "bksp" | "back_space" | "back" | "\x08" | "⌫" => (VK_BACK, false, 0x0E),
            "tab" => (VK_TAB, false, 0x0F),
            "enter" | "return" | "\n" | "\r" => (VK_RETURN, false, 0x1C),
            "space" | " " => (VK_SPACE, false, 0x39),
            "escape" | "esc" => (VK_ESCAPE, false, 0x01),
            "arrowup" | "up" => (VK_UP, true, 0x48),
            "arrowdown" | "down" => (VK_DOWN, true, 0x50),
            "arrowleft" | "left" => (VK_LEFT, true, 0x4B),
            "arrowright" | "right" => (VK_RIGHT, true, 0x4D),
            "home" => (VK_HOME, true, 0x47),
            "end" => (VK_END, true, 0x4F),
            "pageup" | "prior" => (VK_PRIOR, true, 0x49),
            "pagedown" | "next" => (VK_NEXT, true, 0x51),
            "delete" | "del" => (VK_DELETE, true, 0x53),
            "insert" | "ins" => (0x2D, true, 0x52),
            "win" | "meta" | "lwin" => (VK_LWIN, true, 0x5B),
            "capslock" | "caps" => (0x14, false, 0x3A),
            "f1" => (0x70, false, 0x3B),
            "f2" => (0x71, false, 0x3C),
            "f3" => (0x72, false, 0x3D),
            "f4" => (0x73, false, 0x3E),
            "f5" => (0x74, false, 0x3F),
            "f6" => (0x75, false, 0x40),
            "f7" => (0x76, false, 0x41),
            "f8" => (0x77, false, 0x42),
            "f9" => (0x78, false, 0x43),
            "f10" => (0x79, false, 0x44),
            "f11" => (0x7A, false, 0x57),
            "f12" => (0x7B, false, 0x58),
            _ => (0, false, 0),
        };

        if vk == 0 {
            if key.chars().count() == 1 {
                self.send_text(key);
            }
            return;
        }

        let mapped_scan = unsafe { MapVirtualKeyW(vk as u32, 0) } as u16;
        let scan = if mapped_scan != 0 { mapped_scan } else { default_scan };
        let ext_flag = if is_extended { KEYEVENTF_EXTENDEDKEY } else { 0 };

        let mut mod_inputs_down: Vec<INPUT> = Vec::new();
        let mut mod_inputs_up: Vec<INPUT> = Vec::new();

        for mod_name in modifiers {
            let mod_vk = match mod_name.to_lowercase().as_str() {
                "ctrl" | "control" => VK_CONTROL,
                "shift" => VK_SHIFT,
                "alt" => VK_MENU,
                "meta" | "win" => VK_LWIN,
                _ => 0,
            };
            if mod_vk != 0 {
                let mod_scan = unsafe { MapVirtualKeyW(mod_vk as u32, 0) } as u16;
                let mut down: INPUT = unsafe { zeroed() };
                down.r#type = INPUT_KEYBOARD;
                down.u.ki.wVk = mod_vk;
                down.u.ki.wScan = mod_scan;
                mod_inputs_down.push(down);

                let mut up: INPUT = unsafe { zeroed() };
                up.r#type = INPUT_KEYBOARD;
                up.u.ki.wVk = mod_vk;
                up.u.ki.wScan = mod_scan;
                up.u.ki.dwFlags = KEYEVENTF_KEYUP;
                mod_inputs_up.push(up);
            }
        }

        // 1. Modifiers down
        if !mod_inputs_down.is_empty() && (action == "down" || action == "press") {
            safe_send_input(&mut mod_inputs_down);
        }

        // 2. Primary key action
        if action == "down" {
            let mut down: INPUT = unsafe { zeroed() };
            down.r#type = INPUT_KEYBOARD;
            down.u.ki.wVk = vk;
            down.u.ki.wScan = scan;
            down.u.ki.dwFlags = ext_flag;
            safe_send_input(&mut [down]);
        } else if action == "up" {
            let mut up: INPUT = unsafe { zeroed() };
            up.r#type = INPUT_KEYBOARD;
            up.u.ki.wVk = vk;
            up.u.ki.wScan = scan;
            up.u.ki.dwFlags = ext_flag | KEYEVENTF_KEYUP;
            safe_send_input(&mut [up]);
        } else {
            // action == "press"
            let mut down: INPUT = unsafe { zeroed() };
            down.r#type = INPUT_KEYBOARD;
            down.u.ki.wVk = vk;
            down.u.ki.wScan = scan;
            down.u.ki.dwFlags = ext_flag;
            safe_send_input(&mut [down]);

            // 10ms hardware keystroke hold ensures all Windows apps dispatch WM_KEYDOWN & WM_CHAR
            std::thread::sleep(std::time::Duration::from_millis(10));

            let mut up: INPUT = unsafe { zeroed() };
            up.r#type = INPUT_KEYBOARD;
            up.u.ki.wVk = vk;
            up.u.ki.wScan = scan;
            up.u.ki.dwFlags = ext_flag | KEYEVENTF_KEYUP;
            safe_send_input(&mut [up]);
        }

        // 3. Modifiers up
        if !mod_inputs_up.is_empty() && (action == "up" || action == "press") {
            safe_send_input(&mut mod_inputs_up);
        }
    }

    /// System shortcuts
    pub fn send_shortcut(&self, action: &str) {
        match action {
            "copy" => self.send_key_combo(VK_CONTROL, 0x43),       // Ctrl + C
            "paste" => self.send_key_combo(VK_CONTROL, 0x56),      // Ctrl + V
            "cut" => self.send_key_combo(VK_CONTROL, 0x58),        // Ctrl + X
            "undo" => self.send_key_combo(VK_CONTROL, 0x5A),       // Ctrl + Z
            "redo" => self.send_key_combo(VK_CONTROL, 0x59),       // Ctrl + Y
            "select_all" => self.send_key_combo(VK_CONTROL, 0x41), // Ctrl + A
            "save" => self.send_key_combo(VK_CONTROL, 0x53),       // Ctrl + S
            "find" => self.send_key_combo(VK_CONTROL, 0x46),       // Ctrl + F
            "new_tab" => self.send_key_combo(VK_CONTROL, 0x54),    // Ctrl + T
            "close_tab" => self.send_key_combo(VK_CONTROL, 0x57),  // Ctrl + W
            "refresh" => self.send_key_direct(0x74),               // F5
            "desktop" | "show_desktop" => {
                self.send_key_combo(VK_LWIN, 0x44);       // Win + D
                // Shell COM fallback guarantees desktop toggle even when exclusive window is active
                let _ = std::process::Command::new("powershell.exe")
                    .args(&["-WindowStyle", "Hidden", "-Command", "(New-Object -ComObject Shell.Application).ToggleDesktop()"])
                    .spawn();
            }
            "app_switcher" | "switch_window" => self.send_key_combo(VK_MENU, VK_TAB),// Alt + Tab
            "close_window" => self.send_key_combo(VK_MENU, 0x73),                   // Alt + F4
            "minimize" => {
                self.send_key_combo(VK_LWIN, 0x4D);                       // Win + M
                let _ = std::process::Command::new("powershell.exe")
                    .args(&["-WindowStyle", "Hidden", "-Command", "(New-Object -ComObject Shell.Application).MinimizeAll()"])
                    .spawn();
            }
            "maximize" => self.send_key_combo(VK_LWIN, VK_UP),                      // Win + Up
            "screenshot" => self.send_key_combo(VK_LWIN, 0x2C),                     // Win + PrtScn
            "lock" => {
                let _ = std::process::Command::new("rundll32.exe")
                    .args(&["user32.dll,LockWorkStation"])
                    .spawn();
            }
            "volume_up" => self.send_key_direct(VK_VOLUME_UP),
            "volume_down" => self.send_key_direct(VK_VOLUME_DOWN),
            "mute" => self.send_key_direct(VK_VOLUME_MUTE),
            "media_play_pause" => self.send_key_direct(0xB3),                       // VK_MEDIA_PLAY_PAUSE
            "media_next" => self.send_key_direct(0xB0),                             // VK_MEDIA_NEXT_TRACK
            "media_prev" => self.send_key_direct(0xB1),                             // VK_MEDIA_PREV_TRACK
            _ => {}
        }
    }

    fn send_key_combo(&self, modifier: u16, key: u16) {
        let is_mod_ext = modifier == VK_LWIN || modifier == 0x5C;
        let is_key_ext = key == VK_UP || key == VK_DOWN || key == VK_LEFT || key == VK_RIGHT
            || key == VK_HOME || key == VK_END || key == VK_PRIOR || key == VK_NEXT || key == VK_DELETE;

        let mod_scan = unsafe { MapVirtualKeyW(modifier as u32, 0) } as u16;
        let key_scan = unsafe { MapVirtualKeyW(key as u32, 0) } as u16;

        let mut down_mod: INPUT = unsafe { zeroed() };
        down_mod.r#type = INPUT_KEYBOARD;
        down_mod.u.ki.wVk = modifier;
        down_mod.u.ki.wScan = mod_scan;
        down_mod.u.ki.dwFlags = if is_mod_ext { KEYEVENTF_EXTENDEDKEY } else { 0 };

        let mut down_key: INPUT = unsafe { zeroed() };
        down_key.r#type = INPUT_KEYBOARD;
        down_key.u.ki.wVk = key;
        down_key.u.ki.wScan = key_scan;
        down_key.u.ki.dwFlags = if is_key_ext { KEYEVENTF_EXTENDEDKEY } else { 0 };

        safe_send_input(&mut [down_mod]);
        std::thread::sleep(std::time::Duration::from_millis(20));

        safe_send_input(&mut [down_key]);
        std::thread::sleep(std::time::Duration::from_millis(30));

        let mut up_key: INPUT = unsafe { zeroed() };
        up_key.r#type = INPUT_KEYBOARD;
        up_key.u.ki.wVk = key;
        up_key.u.ki.wScan = key_scan;
        up_key.u.ki.dwFlags = (if is_key_ext { KEYEVENTF_EXTENDEDKEY } else { 0 }) | KEYEVENTF_KEYUP;

        safe_send_input(&mut [up_key]);
        std::thread::sleep(std::time::Duration::from_millis(20));

        let mut up_mod: INPUT = unsafe { zeroed() };
        up_mod.r#type = INPUT_KEYBOARD;
        up_mod.u.ki.wVk = modifier;
        up_mod.u.ki.wScan = mod_scan;
        up_mod.u.ki.dwFlags = (if is_mod_ext { KEYEVENTF_EXTENDEDKEY } else { 0 }) | KEYEVENTF_KEYUP;

        safe_send_input(&mut [up_mod]);
    }

    fn send_key_direct(&self, vk: u16) {
        let scan = unsafe { MapVirtualKeyW(vk as u32, 0) } as u16;

        let mut down: INPUT = unsafe { zeroed() };
        down.r#type = INPUT_KEYBOARD;
        down.u.ki.wVk = vk;
        down.u.ki.wScan = scan;

        safe_send_input(&mut [down]);

        std::thread::sleep(std::time::Duration::from_millis(10));

        let mut up: INPUT = unsafe { zeroed() };
        up.r#type = INPUT_KEYBOARD;
        up.u.ki.wVk = vk;
        up.u.ki.wScan = scan;
        up.u.ki.dwFlags = KEYEVENTF_KEYUP;

        safe_send_input(&mut [up]);
    }
}
