#![cfg(target_os = "macos")]

use std::ptr;
use core_foundation::base::TCFType;
use core_foundation::boolean::CFBoolean;
use core_foundation::dictionary::CFDictionary;
use core_foundation::string::CFString;

#[repr(C)]
struct CGPoint {
    x: f64,
    y: f64,
}

type CGEventRef = *mut std::ffi::c_void;
type CGEventSourceRef = *mut std::ffi::c_void;

const K_CG_EVENT_LEFT_MOUSE_DOWN: u32 = 1;
const K_CG_EVENT_LEFT_MOUSE_UP: u32 = 2;
const K_CG_EVENT_RIGHT_MOUSE_DOWN: u32 = 3;
const K_CG_EVENT_RIGHT_MOUSE_UP: u32 = 4;
const K_CG_EVENT_MOUSE_MOVED: u32 = 5;
const K_CG_EVENT_LEFT_MOUSE_DRAGGED: u32 = 6;
const K_CG_EVENT_RIGHT_MOUSE_DRAGGED: u32 = 7;
const K_CG_EVENT_OTHER_MOUSE_DOWN: u32 = 25;
const K_CG_EVENT_OTHER_MOUSE_UP: u32 = 26;
const K_CG_EVENT_SCROLL_WHEEL: u32 = 22;
const K_CG_EVENT_KEY_DOWN: u32 = 10;
const K_CG_EVENT_KEY_UP: u32 = 11;

const K_CG_HID_EVENT_TAP: u32 = 0;
const K_CG_MOUSE_BUTTON_LEFT: u32 = 0;
const K_CG_MOUSE_BUTTON_RIGHT: u32 = 1;
const K_CG_MOUSE_BUTTON_CENTER: u32 = 2;

#[link(name = "CoreGraphics", kind = "framework")]
extern "C" {
    fn CGEventCreate(source: CGEventSourceRef) -> CGEventRef;
    fn CGEventGetLocation(event: CGEventRef) -> CGPoint;
    fn CGEventCreateMouseEvent(
        source: CGEventSourceRef,
        mouseType: u32,
        mouseCursorPosition: CGPoint,
        mouseButton: u32,
    ) -> CGEventRef;
    fn CGEventCreateScrollWheelEvent2(
        source: CGEventSourceRef,
        units: u32,
        wheelCount: u32,
        wheel1: i32,
        wheel2: i32,
        wheel3: i32,
    ) -> CGEventRef;
    fn CGEventCreateKeyboardEvent(
        source: CGEventSourceRef,
        virtualKey: u16,
        keyDown: bool,
    ) -> CGEventRef;
    fn CGEventKeyboardSetUnicodeString(
        event: CGEventRef,
        stringLength: usize,
        unicodeString: *const u16,
    );
    fn CGEventPost(tap: u32, event: CGEventRef);
    fn CFRelease(cf: *const std::ffi::c_void);
}

#[link(name = "ApplicationServices", kind = "framework")]
extern "C" {
    fn AXIsProcessTrustedWithOptions(options: *const std::ffi::c_void) -> bool;
}

pub struct MacOsDriver;

impl MacOsDriver {
    pub fn new() -> Self {
        MacOsDriver
    }

    /// Check if Accessibility Permissions are granted
    pub fn check_accessibility(prompt: bool) -> bool {
        unsafe {
            if prompt {
                let key = CFString::new("AXTrustedCheckOptionPrompt");
                let val = CFBoolean::true_value();
                let dict = CFDictionary::from_CFType_pairs(&[(key.as_CFType(), val.as_CFType())]);
                AXIsProcessTrustedWithOptions(dict.as_concrete_TypeRef() as *const _)
            } else {
                AXIsProcessTrustedWithOptions(ptr::null())
            }
        }
    }

    /// Move mouse relative to current location
    pub fn mouse_move(&self, dx: f64, dy: f64) {
        unsafe {
            let current = CGEventCreate(ptr::null_mut());
            if current.is_null() {
                return;
            }
            let loc = CGEventGetLocation(current);
            CFRelease(current as *const _);

            let new_loc = CGPoint {
                x: loc.x + dx,
                y: loc.y + dy,
            };

            let move_ev = CGEventCreateMouseEvent(
                ptr::null_mut(),
                K_CG_EVENT_MOUSE_MOVED,
                new_loc,
                K_CG_MOUSE_BUTTON_LEFT,
            );
            if !move_ev.is_null() {
                CGEventPost(K_CG_HID_EVENT_TAP, move_ev);
                CFRelease(move_ev as *const _);
            }
        }
    }

    /// Mouse clicking (left, right, middle)
    pub fn mouse_click(&self, button: &str, action: &str) {
        unsafe {
            let current = CGEventCreate(ptr::null_mut());
            if current.is_null() {
                return;
            }
            let loc = CGEventGetLocation(current);
            CFRelease(current as *const _);

            let (btn_code, down_type, up_type) = match button {
                "right" => (K_CG_MOUSE_BUTTON_RIGHT, K_CG_EVENT_RIGHT_MOUSE_DOWN, K_CG_EVENT_RIGHT_MOUSE_UP),
                "middle" => (K_CG_MOUSE_BUTTON_CENTER, K_CG_EVENT_OTHER_MOUSE_DOWN, K_CG_EVENT_OTHER_MOUSE_UP),
                _ => (K_CG_MOUSE_BUTTON_LEFT, K_CG_EVENT_LEFT_MOUSE_DOWN, K_CG_EVENT_LEFT_MOUSE_UP),
            };

            match action {
                "down" => {
                    let ev = CGEventCreateMouseEvent(ptr::null_mut(), down_type, loc, btn_code);
                    if !ev.is_null() {
                        CGEventPost(K_CG_HID_EVENT_TAP, ev);
                        CFRelease(ev as *const _);
                    }
                }
                "up" => {
                    let ev = CGEventCreateMouseEvent(ptr::null_mut(), up_type, loc, btn_code);
                    if !ev.is_null() {
                        CGEventPost(K_CG_HID_EVENT_TAP, ev);
                        CFRelease(ev as *const _);
                    }
                }
                _ => { // click
                    let down = CGEventCreateMouseEvent(ptr::null_mut(), down_type, loc, btn_code);
                    let up = CGEventCreateMouseEvent(ptr::null_mut(), up_type, loc, btn_code);
                    if !down.is_null() {
                        CGEventPost(K_CG_HID_EVENT_TAP, down);
                        CFRelease(down as *const _);
                    }
                    if !up.is_null() {
                        CGEventPost(K_CG_HID_EVENT_TAP, up);
                        CFRelease(up as *const _);
                    }
                }
            }
        }
    }

    /// Scroll vertically and horizontally
    pub fn mouse_scroll(&self, dx: f64, dy: f64) {
        unsafe {
            // Units: 0 = lines, 1 = pixels
            let ev = CGEventCreateScrollWheelEvent2(
                ptr::null_mut(),
                0,
                2,
                dy.round() as i32,
                dx.round() as i32,
                0,
            );
            if !ev.is_null() {
                CGEventPost(K_CG_HID_EVENT_TAP, ev);
                CFRelease(ev as *const _);
            }
        }
    }

    /// Full Unicode text injection on macOS (Urdu, English, emojis)
    pub fn send_text(&self, text: &str) {
        let utf16: Vec<u16> = text.encode_utf16().collect();
        if utf16.is_empty() {
            return;
        }

        unsafe {
            let ev = CGEventCreateKeyboardEvent(ptr::null_mut(), 0, true);
            if !ev.is_null() {
                CGEventKeyboardSetUnicodeString(ev, utf16.len(), utf16.as_ptr());
                CGEventPost(K_CG_HID_EVENT_TAP, ev);
                CFRelease(ev as *const _);
            }
        }
    }

    /// Keyboard key event
    pub fn send_key(&self, key: &str, _action: &str, _modifiers: &[String]) {
        let keycode = match key {
            "Backspace" => 0x33,
            "Tab" => 0x30,
            "Enter" => 0x24,
            "Space" => 0x31,
            "Escape" => 0x35,
            "ArrowUp" => 0x7E,
            "ArrowDown" => 0x7D,
            "ArrowLeft" => 0x7B,
            "ArrowRight" => 0x7C,
            _ => 0xFFFF,
        };

        if keycode != 0xFFFF {
            unsafe {
                let down = CGEventCreateKeyboardEvent(ptr::null_mut(), keycode, true);
                let up = CGEventCreateKeyboardEvent(ptr::null_mut(), keycode, false);
                if !down.is_null() {
                    CGEventPost(K_CG_HID_EVENT_TAP, down);
                    CFRelease(down as *const _);
                }
                if !up.is_null() {
                    CGEventPost(K_CG_HID_EVENT_TAP, up);
                    CFRelease(up as *const _);
                }
            }
        } else if key.chars().count() == 1 {
            self.send_text(key);
        }
    }

    /// System shortcuts on macOS (Cmd+C, Cmd+V, etc.)
    pub fn send_shortcut(&self, action: &str) {
        match action {
            "copy" => self.send_text(""), // or CGEvent with Command flag
            _ => {}
        }
    }
}
