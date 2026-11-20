#![cfg(target_os = "windows")]
#![allow(non_snake_case, dead_code)]

use std::sync::Arc;
use std::ffi::c_void;
use crate::AppState;
use qrcode::{Color as QrColor, QrCode};

// Win32 Types
type HWND = *mut c_void;
type HDC = *mut c_void;
type HBRUSH = *mut c_void;
type HFONT = *mut c_void;
type HICON = *mut c_void;
type HMENU = *mut c_void;
type HINSTANCE = *mut c_void;
type LRESULT = isize;
type WPARAM = usize;
type LPARAM = isize;
type UINT = u32;
type BOOL = i32;

#[repr(C)]
struct WNDCLASSEXW {
    cbSize: UINT,
    style: UINT,
    lpfnWndProc: Option<unsafe extern "system" fn(HWND, UINT, WPARAM, LPARAM) -> LRESULT>,
    cbClsExtra: i32,
    cbWndExtra: i32,
    hInstance: HINSTANCE,
    hIcon: HICON,
    hCursor: *mut c_void,
    hbrBackground: HBRUSH,
    lpszMenuName: *const u16,
    lpszClassName: *const u16,
    hIconSm: HICON,
}

#[repr(C)]
struct POINT {
    x: i32,
    y: i32,
}

#[repr(C)]
struct MSG {
    hwnd: HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: u32,
    pt: POINT,
    lPrivate: u32,
}

#[repr(C)]
struct RECT {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
}

#[repr(C)]
struct PAINTSTRUCT {
    hdc: HDC,
    fErase: BOOL,
    rcPaint: RECT,
    fRestore: BOOL,
    fIncUpdate: BOOL,
    rgbReserved: [u8; 32],
}

#[repr(C)]
struct NOTIFYICONDATAW {
    cbSize: u32,
    hWnd: HWND,
    uID: u32,
    uFlags: u32,
    uCallbackMessage: u32,
    hIcon: HICON,
    szTip: [u16; 128],
    dwState: u32,
    dwStateMask: u32,
    szInfo: [u16; 256],
    uTimeoutOrVersion: u32,
    szInfoTitle: [u16; 64],
    dwInfoFlags: u32,
    guidItem: [u8; 16],
    hBalloonIcon: HICON,
}

extern "system" {
    fn GetModuleHandleW(lpModuleName: *const u16) -> HINSTANCE;
    fn RegisterClassExW(lpwcx: *const WNDCLASSEXW) -> u16;
    fn CreateWindowExW(
        dwExStyle: u32,
        lpClassName: *const u16,
        lpWindowName: *const u16,
        dwStyle: u32,
        X: i32,
        Y: i32,
        nWidth: i32,
        nHeight: i32,
        hWndParent: HWND,
        hMenu: HMENU,
        hInstance: HINSTANCE,
        lpParam: *mut c_void,
    ) -> HWND;
    fn ShowWindow(hWnd: HWND, nCmdShow: i32) -> BOOL;
    fn UpdateWindow(hWnd: HWND) -> BOOL;
    fn SetForegroundWindow(hWnd: HWND) -> BOOL;
    fn BringWindowToTop(hWnd: HWND) -> BOOL;
    fn DestroyWindow(hWnd: HWND) -> BOOL;
    fn DefWindowProcW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) -> LRESULT;
    fn GetMessageW(lpMsg: *mut MSG, hWnd: HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT) -> BOOL;
    fn TranslateMessage(lpMsg: *const MSG) -> BOOL;
    fn DispatchMessageW(lpMsg: *const MSG) -> LRESULT;
    fn PostQuitMessage(nExitCode: i32);
    fn BeginPaint(hWnd: HWND, lpPaint: *mut PAINTSTRUCT) -> HDC;
    fn EndPaint(hWnd: HWND, lpPaint: *const PAINTSTRUCT) -> BOOL;
    fn FillRect(hDC: HDC, lprc: *const RECT, hbr: HBRUSH) -> i32;
    fn CreateSolidBrush(color: u32) -> HBRUSH;
    fn DeleteObject(ho: *mut c_void) -> BOOL;
    fn SelectObject(hdc: HDC, h: *mut c_void) -> *mut c_void;
    fn SetTextColor(hdc: HDC, color: u32) -> u32;
    fn SetBkMode(hdc: HDC, mode: i32) -> i32;
    fn SetBkColor(hdc: HDC, color: u32) -> u32;
    fn DrawTextW(hdc: HDC, lpchText: *const u16, cchText: i32, lprc: *mut RECT, format: UINT) -> i32;
    fn CreateFontW(
        cHeight: i32, cWidth: i32, cEscapement: i32, cOrientation: i32, cWeight: i32,
        bItalic: u32, bUnderline: u32, bStrikeOut: u32, iCharSet: u32,
        iOutPrecision: u32, iClipPrecision: u32, iQuality: u32, iPitchAndFamily: u32,
        pszFaceName: *const u16,
    ) -> HFONT;
    fn LoadCursorW(hInstance: HINSTANCE, lpCursorName: *const u16) -> *mut c_void;
    fn LoadIconW(hInstance: HINSTANCE, lpIconName: *const u16) -> HICON;
    fn InvalidateRect(hWnd: HWND, lpRect: *const RECT, bErase: BOOL) -> BOOL;
    fn GetClientRect(hWnd: HWND, lpRect: *mut RECT) -> BOOL;
    fn GetSystemMetrics(nIndex: i32) -> i32;
    fn SetWindowPos(hWnd: HWND, hWndInsertAfter: HWND, X: i32, Y: i32, cx: i32, cy: i32, uFlags: u32) -> BOOL;
    fn IsWindow(hWnd: HWND) -> BOOL;
    fn Shell_NotifyIconW(dwMessage: u32, lpData: *mut NOTIFYICONDATAW) -> BOOL;
    fn CreatePopupMenu() -> HMENU;
    fn AppendMenuW(hMenu: HMENU, uFlags: UINT, uIDNewItem: usize, lpNewItem: *const u16) -> BOOL;
    fn TrackPopupMenu(hMenu: HMENU, uFlags: UINT, x: i32, y: i32, nReserved: i32, hWnd: HWND, prcRect: *const RECT) -> BOOL;
    fn DestroyMenu(hMenu: HMENU) -> BOOL;
    fn GetCursorPos(lpPoint: *mut POINT) -> BOOL;
    fn GetLastError() -> u32;
    fn SetWindowLongPtrW(hWnd: HWND, nIndex: i32, dwNewLong: isize) -> isize;
    fn GetWindowLongPtrW(hWnd: HWND, nIndex: i32) -> isize;
    fn RoundRect(hdc: HDC, left: i32, top: i32, right: i32, bottom: i32, width: i32, height: i32) -> BOOL;
    fn CreatePen(iStyle: i32, cWidth: i32, color: u32) -> *mut c_void;
    fn SetTimer(hWnd: HWND, nIDEvent: usize, uElapse: u32, lpTimerFunc: Option<unsafe extern "system" fn(HWND, UINT, usize, u32)>) -> usize;
    fn AllowSetForegroundWindow(dwProcessId: u32) -> BOOL;
    fn CreateCompatibleDC(hdc: HDC) -> HDC;
    fn CreateCompatibleBitmap(hdc: HDC, cx: i32, cy: i32) -> *mut c_void;
    fn DeleteDC(hdc: HDC) -> BOOL;
    fn BitBlt(hdc: HDC, x: i32, y: i32, cx: i32, cy: i32, hdcSrc: HDC, x1: i32, y1: i32, rop: u32) -> BOOL;
    fn LoadImageW(hInst: HINSTANCE, name: *const u16, type_: u32, cx: i32, cy: i32, fuLoad: u32) -> *mut c_void;
    fn SendMessageW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) -> LRESULT;
    fn MessageBoxW(hWnd: HWND, lpText: *const u16, lpCaption: *const u16, uType: UINT) -> i32;
}

// Window Constants
const WS_OVERLAPPED: u32 = 0x00000000;
const WS_CAPTION: u32 = 0x00C00000;
const WS_SYSMENU: u32 = 0x00080000;
const WS_MINIMIZEBOX: u32 = 0x00020000;
const WS_VISIBLE: u32 = 0x10000000;
const WS_CHILD: u32 = 0x40000000;
const WS_TABSTOP: u32 = 0x00010000;
const BS_DEFPUSHBUTTON: u32 = 0x00000001;
const BS_PUSHBUTTON: u32 = 0x00000000;

const WM_CREATE: UINT = 0x0001;
const WM_DESTROY: UINT = 0x0002;
const WM_PAINT: UINT = 0x000F;
const WM_CLOSE: UINT = 0x0010;
const WM_ERASEBKGND: UINT = 0x0014;
const WM_SETICON: UINT = 0x0080;
const WM_COMMAND: UINT = 0x0111;
const WM_TIMER: UINT = 0x0113;
const WM_USER: UINT = 0x0400;
const WM_TRAYICON: UINT = WM_USER + 101;
const WM_SHOW_WINDOW: UINT = WM_USER + 102;

const SRCCOPY: u32 = 0x00CC0020;
const ICON_SMALL: WPARAM = 0;
const ICON_BIG: WPARAM = 1;
const IMAGE_ICON: u32 = 1;
const LR_LOADFROMFILE: u32 = 0x0010;
const LR_DEFAULTSIZE: u32 = 0x0040;

const SW_HIDE: i32 = 0;
const SW_SHOW: i32 = 5;
const SW_RESTORE: i32 = 9;

const DT_LEFT: UINT = 0x00000000;
const DT_CENTER: UINT = 0x00000001;
const DT_RIGHT: UINT = 0x00000002;
const DT_VCENTER: UINT = 0x00000004;
const DT_SINGLELINE: UINT = 0x00000020;
const DT_WORDBREAK: UINT = 0x00000010;

const NIM_ADD: u32 = 0;
const NIM_MODIFY: u32 = 1;
const NIM_DELETE: u32 = 2;
const NIF_MESSAGE: u32 = 1;
const NIF_ICON: u32 = 2;
const NIF_TIP: u32 = 4;
const NIF_INFO: u32 = 16;
const NIIF_INFO: u32 = 1;

const TPM_RIGHTBUTTON: UINT = 0x0002;

const ID_BTN_NEWPIN: usize = 2001;
const ID_BTN_MINIMIZE: usize = 2002;
const ID_BTN_EXIT: usize = 2003;
const ID_TRAY_OPEN: usize = 3001;
const ID_TRAY_EXIT: usize = 3002;
const ID_TRAY_DISC_BASE: usize = 3100;
const ID_TRAY_REM_BASE: usize = 3200;

// Colors in BGR format for Win32 GDI
const COLOR_BG: u32 = 0x2A170F;        // Slate 900 #0F172A (BGR: 0x2A170F)
const COLOR_CARD: u32 = 0x3B291E;      // Slate 800 #1E293B (BGR: 0x3B291E)
const COLOR_CARD_BORDER: u32 = 0x524133;// Slate 700 #334152 (BGR: 0x524133)
const COLOR_TEXT_WHITE: u32 = 0xFAF8F8; // #F8FAF8
const COLOR_TEXT_MUTED: u32 = 0xB8A394; // Slate 400 #94A3B8 (BGR: 0xB8A394)
const COLOR_GREEN: u32 = 0x5EC522;      // Emerald Green #22C55E (BGR: 0x5EC522)
const COLOR_CYAN: u32 = 0xF8BD38;       // Sky Blue #38BDF8 (BGR: 0xF8BD38)
const COLOR_GOLD: u32 = 0x15CCFA;       // Amber Gold #FACC15 (BGR: 0x15CCFA)
const COLOR_RED: u32 = 0x4755EF;        // Red #EF5547 (BGR: 0x4755EF)
const COLOR_BTN_DISC: u32 = 0x503014;   // Dark Cyan/Navy Pill
const COLOR_BTN_REM: u32 = 0x181845;    // Dark Red Pill

// Global reference for WndProc
static mut GLOBAL_STATE: Option<Arc<AppState>> = None;
static mut GLOBAL_HWND: HWND = std::ptr::null_mut();

pub fn request_gui_repaint() {
    unsafe {
        if !GLOBAL_HWND.is_null() {
            InvalidateRect(GLOBAL_HWND, std::ptr::null(), 0);
        }
    }
}

fn to_wide(s: &str) -> Vec<u16> {
    use std::ffi::OsStr;
    use std::os::windows::ffi::OsStrExt;
    OsStr::new(s).encode_wide().chain(std::iter::once(0)).collect()
}

unsafe extern "system" fn window_proc(hwnd: HWND, msg: UINT, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    match msg {
        WM_ERASEBKGND => {
            // Prevent Windows from erasing the client area with the default white/gray brush
            1
        }
        WM_CREATE => {
            GLOBAL_HWND = hwnd;
            // Set up 1-second refresh timer to update client list and status
            SetTimer(hwnd, 1, 1000, None);

            // Create buttons
            let h_inst = GetModuleHandleW(std::ptr::null());
            let btn_class = to_wide("BUTTON");

            let txt_pin = to_wide("New PIN");
            CreateWindowExW(
                0, btn_class.as_ptr(), txt_pin.as_ptr(),
                WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON,
                55, 252, 110, 34,
                hwnd, ID_BTN_NEWPIN as HMENU, h_inst, std::ptr::null_mut(),
            );

            let txt_min = to_wide("Minimize to Tray");
            CreateWindowExW(
                0, btn_class.as_ptr(), txt_min.as_ptr(),
                WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON,
                345, 470, 135, 36,
                hwnd, ID_BTN_MINIMIZE as HMENU, h_inst, std::ptr::null_mut(),
            );

            let txt_exit = to_wide("Exit Server");
            CreateWindowExW(
                0, btn_class.as_ptr(), txt_exit.as_ptr(),
                WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON,
                495, 470, 110, 36,
                hwnd, ID_BTN_EXIT as HMENU, h_inst, std::ptr::null_mut(),
            );

            0
        }
        WM_TIMER => {
            // Repaint without background erase for rock-solid flicker-free rendering
            let mut rc = RECT { left: 0, top: 0, right: 0, bottom: 0 };
            GetClientRect(hwnd, &mut rc);
            InvalidateRect(hwnd, &rc, 0);
            0
        }
        WM_COMMAND => {
            let notify_code = (wparam >> 16) & 0xFFFF;
            // If from a control (lparam != null), only process BN_CLICKED (0)
            if lparam != 0 && notify_code != 0 {
                return 0;
            }
            let id = wparam & 0xFFFF;
            match id {
                ID_BTN_NEWPIN => {
                    if let Some(ref state) = GLOBAL_STATE {
                        let new_pin = format!("{:06}", rand::random::<u32>() % 1_000_000);
                        state.auth_manager.set_pin(new_pin);
                        let mut rc = RECT { left: 0, top: 0, right: 0, bottom: 0 };
                        GetClientRect(hwnd, &mut rc);
                        InvalidateRect(hwnd, &rc, 0);
                    }
                }
                ID_BTN_MINIMIZE => {
                    ShowWindow(hwnd, SW_HIDE);
                }
                ID_BTN_EXIT => {
                    let confirm_msg = to_wide("Are you sure you want to stop and exit the Mobile Kemo server?\n\nThis will disconnect all active mobile sessions.");
                    let confirm_title = to_wide("Confirm Exit - Mobile Kemo");
                    let res = MessageBoxW(hwnd, confirm_msg.as_ptr(), confirm_title.as_ptr(), 0x00000004 /* MB_YESNO */ | 0x00000030 /* MB_ICONQUESTION */ | 0x00000100 /* MB_DEFBUTTON2 */);
                    if res == 6 /* IDYES */ {
                        remove_tray_icon(hwnd);
                        DestroyWindow(hwnd);
                    }
                }
                ID_TRAY_OPEN => {
                    ShowWindow(hwnd, 1 /* SW_SHOWNORMAL */);
                    ShowWindow(hwnd, SW_RESTORE);
                    ShowWindow(hwnd, SW_SHOW);
                    SetForegroundWindow(hwnd);
                    BringWindowToTop(hwnd);
                }
                ID_TRAY_EXIT => {
                    let confirm_msg = to_wide("Are you sure you want to stop and exit the Mobile Kemo server?\n\nThis will disconnect all active mobile sessions.");
                    let confirm_title = to_wide("Confirm Exit - Mobile Kemo");
                    let res = MessageBoxW(hwnd, confirm_msg.as_ptr(), confirm_title.as_ptr(), 0x00000004 /* MB_YESNO */ | 0x00000030 /* MB_ICONQUESTION */ | 0x00000100 /* MB_DEFBUTTON2 */);
                    if res == 6 /* IDYES */ {
                        remove_tray_icon(hwnd);
                        DestroyWindow(hwnd);
                    }
                }
                _ if id >= ID_TRAY_DISC_BASE && id < ID_TRAY_DISC_BASE + 20 => {
                    let idx = id - ID_TRAY_DISC_BASE;
                    if let Some(ref state) = GLOBAL_STATE {
                        let clients_guard = state.clients.lock().unwrap();
                        let target_id = clients_guard.values().nth(idx).map(|c| c.id.clone());
                        drop(clients_guard);
                        if let Some(dev_id) = target_id {
                            state.disconnect_client(&dev_id);
                            InvalidateRect(hwnd, std::ptr::null(), 0);
                        }
                    }
                }
                _ if id >= ID_TRAY_REM_BASE && id < ID_TRAY_REM_BASE + 20 => {
                    let idx = id - ID_TRAY_REM_BASE;
                    if let Some(ref state) = GLOBAL_STATE {
                        let clients_guard = state.clients.lock().unwrap();
                        let target_info = clients_guard.values().nth(idx).map(|c| (c.id.clone(), c.name.clone()));
                        drop(clients_guard);
                        if let Some((dev_id, dev_name)) = target_info {
                            let confirm_msg = to_wide(&format!("Are you sure you want to permanently remove and revoke '{}'?\n\nThis will delete saved authorization on both PC and mobile device.", dev_name));
                            let confirm_title = to_wide("Confirm Device Removal");
                            let res = MessageBoxW(hwnd, confirm_msg.as_ptr(), confirm_title.as_ptr(), 0x00000004 /* MB_YESNO */ | 0x00000030 /* MB_ICONWARNING */ | 0x00000100 /* MB_DEFBUTTON2 */);
                            if res == 6 /* IDYES */ {
                                state.remove_and_revoke_client(&dev_id);
                                InvalidateRect(hwnd, std::ptr::null(), 0);
                            }
                        }
                    }
                }
                _ => {}
            }
            0
        }
        WM_PAINT => {
            let mut ps: PAINTSTRUCT = std::mem::zeroed();
            let hdc_paint = BeginPaint(hwnd, &mut ps);

            let mut rc = RECT { left: 0, top: 0, right: 0, bottom: 0 };
            GetClientRect(hwnd, &mut rc);
            let win_w = rc.right - rc.left;
            let win_h = rc.bottom - rc.top;

            // Double Buffering: Draw to memory DC first to eliminate all blinking & tearing
            let hdc = CreateCompatibleDC(hdc_paint);
            let mem_bmp = CreateCompatibleBitmap(hdc_paint, win_w, win_h);
            let old_bmp = SelectObject(hdc, mem_bmp as *mut c_void);

            let mut rc = RECT { left: 0, top: 0, right: 0, bottom: 0 };
            GetClientRect(hwnd, &mut rc);

            // Fill background with Slate 900
            let bg_brush = CreateSolidBrush(COLOR_BG);
            FillRect(hdc, &rc, bg_brush);
            DeleteObject(bg_brush as *mut c_void);

            SetBkMode(hdc, 1); // TRANSPARENT

            let font_name = to_wide("Segoe UI");

            // 1. Header Title: "Mobile Kemo Desktop Agent"
            let hfont_title = CreateFontW(
                24, 0, 0, 0, 700, 0, 0, 0, 1, 0, 0, 5, 0, font_name.as_ptr(),
            );
            let old_font = SelectObject(hdc, hfont_title as *mut c_void);
            SetTextColor(hdc, COLOR_TEXT_WHITE);

            let title_text = to_wide("Mobile Kemo");
            let mut rc_title = RECT { left: 35, top: 22, right: 600, bottom: 55 };
            DrawTextW(hdc, title_text.as_ptr(), -1, &mut rc_title, DT_LEFT | DT_SINGLELINE);

            // Header Subtitle
            let hfont_sub = CreateFontW(
                14, 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, font_name.as_ptr(),
            );
            SelectObject(hdc, hfont_sub as *mut c_void);
            SetTextColor(hdc, COLOR_TEXT_MUTED);

            let sub_text = to_wide("Wireless Keyboard, Mouse & Screen Streaming Server");
            let mut rc_sub = RECT { left: 35, top: 55, right: 600, bottom: 78 };
            DrawTextW(hdc, sub_text.as_ptr(), -1, &mut rc_sub, DT_LEFT | DT_SINGLELINE);

            // 2. Main Server Info Card (Slate 800 rounded rect)
            let card_brush = CreateSolidBrush(COLOR_CARD);
            let card_pen = CreatePen(0, 1, COLOR_CARD_BORDER);
            let old_brush = SelectObject(hdc, card_brush as *mut c_void);
            let old_pen = SelectObject(hdc, card_pen);

            RoundRect(hdc, 35, 90, 605, 315, 12, 12);

            SelectObject(hdc, old_brush);
            SelectObject(hdc, old_pen);
            DeleteObject(card_brush as *mut c_void);
            DeleteObject(card_pen);

            // Status Indicator inside Card: 🟢 ACTIVE • PORT 58921
            let hfont_status = CreateFontW(
                15, 0, 0, 0, 700, 0, 0, 0, 1, 0, 0, 5, 0, font_name.as_ptr(),
            );
            SelectObject(hdc, hfont_status as *mut c_void);
            SetTextColor(hdc, COLOR_GREEN);

            let status_text = to_wide("● SERVER ACTIVE   (Listening on Port 58921)");
            let mut rc_status = RECT { left: 55, top: 108, right: 400, bottom: 132 };
            DrawTextW(hdc, status_text.as_ptr(), -1, &mut rc_status, DT_LEFT | DT_SINGLELINE);

            // Device Name, IP, PIN
            let hfont_info = CreateFontW(
                15, 0, 0, 0, 600, 0, 0, 0, 1, 0, 0, 5, 0, font_name.as_ptr(),
            );
            SelectObject(hdc, hfont_info as *mut c_void);

            if let Some(ref state) = GLOBAL_STATE {
                // Host Name
                SetTextColor(hdc, COLOR_TEXT_MUTED);
                let host_lbl = to_wide("Computer Name:");
                let mut rc_hl = RECT { left: 55, top: 138, right: 190, bottom: 162 };
                DrawTextW(hdc, host_lbl.as_ptr(), -1, &mut rc_hl, DT_LEFT | DT_SINGLELINE);

                SetTextColor(hdc, COLOR_TEXT_WHITE);
                let host_val = to_wide(&state.server_name);
                let mut rc_hv = RECT { left: 185, top: 138, right: 400, bottom: 162 };
                DrawTextW(hdc, host_val.as_ptr(), -1, &mut rc_hv, DT_LEFT | DT_SINGLELINE);

                // Local IP
                SetTextColor(hdc, COLOR_TEXT_MUTED);
                let ip_lbl = to_wide("Local IP Address:");
                let mut rc_il = RECT { left: 55, top: 165, right: 190, bottom: 188 };
                DrawTextW(hdc, ip_lbl.as_ptr(), -1, &mut rc_il, DT_LEFT | DT_SINGLELINE);

                SetTextColor(hdc, COLOR_CYAN);
                let ip_val = to_wide(&format!("{}:{}", state.get_local_ip(), state.port));
                let mut rc_iv = RECT { left: 185, top: 165, right: 395, bottom: 188 };
                DrawTextW(hdc, ip_val.as_ptr(), -1, &mut rc_iv, DT_LEFT | DT_SINGLELINE);

                // Cloud 4G Relay Status
                SetTextColor(hdc, COLOR_TEXT_MUTED);
                let rly_lbl = to_wide("4G Internet Relay:");
                let mut rc_rl = RECT { left: 55, top: 190, right: 190, bottom: 212 };
                DrawTextW(hdc, rly_lbl.as_ptr(), -1, &mut rc_rl, DT_LEFT | DT_SINGLELINE);

                let tunnel_url = state.get_tunnel_url();
                if tunnel_url.is_empty() {
                    SetTextColor(hdc, COLOR_GOLD);
                    let rly_val = to_wide("Starting Relay...");
                    let mut rc_rv = RECT { left: 185, top: 190, right: 395, bottom: 212 };
                    DrawTextW(hdc, rly_val.as_ptr(), -1, &mut rc_rv, DT_LEFT | DT_SINGLELINE);
                } else {
                    SetTextColor(hdc, COLOR_GREEN);
                    let rly_val = to_wide("ACTIVE (Anywhere / 4G)");
                    let mut rc_rv = RECT { left: 185, top: 190, right: 395, bottom: 212 };
                    DrawTextW(hdc, rly_val.as_ptr(), -1, &mut rc_rv, DT_LEFT | DT_SINGLELINE);
                }

                // Security PIN
                SetTextColor(hdc, COLOR_TEXT_MUTED);
                let pin_lbl = to_wide("Security PIN:");
                let mut rc_pl = RECT { left: 55, top: 218, right: 190, bottom: 248 };
                DrawTextW(hdc, pin_lbl.as_ptr(), -1, &mut rc_pl, DT_LEFT | DT_SINGLELINE);

                let hfont_pin = CreateFontW(
                    22, 0, 0, 0, 700, 0, 0, 0, 1, 0, 0, 5, 0, font_name.as_ptr(),
                );
                SelectObject(hdc, hfont_pin as *mut c_void);
                SetTextColor(hdc, COLOR_GOLD);

                let pin_val = to_wide(&state.auth_manager.get_pin());
                let mut rc_pv = RECT { left: 185, top: 214, right: 380, bottom: 248 };
                DrawTextW(hdc, pin_val.as_ptr(), -1, &mut rc_pv, DT_LEFT | DT_SINGLELINE);

                DeleteObject(hfont_pin as *mut c_void);

                // If 4G tunnel active, show manual connection URL next to New PIN button
                if !tunnel_url.is_empty() {
                    let clean_tunnel = tunnel_url.trim_start_matches("https://").trim_start_matches("http://");
                    let hfont_small = CreateFontW(12, 0, 0, 0, 600, 0, 0, 0, 1, 0, 0, 5, 0, font_name.as_ptr());
                    SelectObject(hdc, hfont_small as *mut c_void);
                    SetTextColor(hdc, COLOR_TEXT_MUTED);
                    let lbl = to_wide("4G / WAN Manual URL:");
                    let mut rc_tu_lbl = RECT { left: 175, top: 250, right: 395, bottom: 266 };
                    DrawTextW(hdc, lbl.as_ptr(), -1, &mut rc_tu_lbl, DT_LEFT | DT_SINGLELINE);

                    SetTextColor(hdc, COLOR_CYAN);
                    let val = to_wide(clean_tunnel);
                    let mut rc_tu_val = RECT { left: 175, top: 266, right: 395, bottom: 286 };
                    DrawTextW(hdc, val.as_ptr(), -1, &mut rc_tu_val, DT_LEFT | DT_SINGLELINE);
                    DeleteObject(hfont_small as *mut c_void);
                    SelectObject(hdc, hfont_info as *mut c_void);
                }

                // Draw QR Code on the right side of Server Info Card
                let cur_ip = state.get_local_ip();
                let qr_json = if tunnel_url.is_empty() {
                    format!(
                        r#"{{"ip":"{}","port":{},"pin":"{}","name":"{}"}}"#,
                        cur_ip,
                        state.port,
                        state.auth_manager.get_pin(),
                        state.server_name
                    )
                } else {
                    let clean_tunnel = tunnel_url.trim_start_matches("https://").trim_start_matches("http://");
                    format!(
                        r#"{{"ip":"{}","port":{},"tunnel":"{}","pin":"{}","name":"{}"}}"#,
                        cur_ip,
                        state.port,
                        clean_tunnel,
                        state.auth_manager.get_pin(),
                        state.server_name
                    )
                };

                if let Ok(code) = QrCode::new(qr_json.as_bytes()) {
                    let qr_modules = code.width();
                    let box_left = 400;
                    let box_top = 98;
                    let box_w = 185;
                    let box_h = 185;

                    // Crisp White background box (extra large for high contrast quiet zone)
                    let white_brush = CreateSolidBrush(0x00FFFFFF);
                    let rc_box = RECT {
                        left: box_left,
                        top: box_top,
                        right: box_left + box_w,
                        bottom: box_top + box_h,
                    };
                    FillRect(hdc, &rc_box, white_brush);
                    DeleteObject(white_brush as *mut c_void);

                    // Draw dark modules with at least 16px quiet zone margin
                    let border = 16;
                    let avail_w = box_w - border * 2;
                    let module_sz = (avail_w / qr_modules as i32).max(1);
                    let actual_qr_sz = module_sz * qr_modules as i32;
                    let qr_start_x = box_left + (box_w - actual_qr_sz) / 2;
                    let qr_start_y = box_top + (box_h - actual_qr_sz) / 2;

                    let black_brush = CreateSolidBrush(0x00000000);
                    for y in 0..qr_modules {
                        for x in 0..qr_modules {
                            if code[(x, y)] == QrColor::Dark {
                                let rc_mod = RECT {
                                    left: qr_start_x + x as i32 * module_sz,
                                    top: qr_start_y + y as i32 * module_sz,
                                    right: qr_start_x + (x as i32 + 1) * module_sz,
                                    bottom: qr_start_y + (y as i32 + 1) * module_sz,
                                };
                                FillRect(hdc, &rc_mod, black_brush);
                            }
                        }
                    }
                    DeleteObject(black_brush as *mut c_void);

                    // Caption below QR Code
                    let hfont_qr_caption = CreateFontW(
                        12, 0, 0, 0, 600, 0, 0, 0, 1, 0, 0, 5, 0, font_name.as_ptr(),
                    );
                    SelectObject(hdc, hfont_qr_caption as *mut c_void);
                    SetTextColor(hdc, COLOR_CYAN);
                    let qr_caption = to_wide("📷 Scan with MobileKemo App");
                    let mut rc_qc = RECT {
                        left: box_left - 20,
                        top: box_top + box_h + 4,
                        right: box_left + box_w + 20,
                        bottom: box_top + box_h + 22,
                    };
                    DrawTextW(hdc, qr_caption.as_ptr(), -1, &mut rc_qc, DT_CENTER | DT_SINGLELINE);

                    if !tunnel_url.is_empty() {
                        SetTextColor(hdc, COLOR_GREEN);
                        let qr_sub = to_wide("● 4G & Wi-Fi Ready");
                        let mut rc_qs = RECT {
                            left: box_left - 20,
                            top: box_top + box_h + 20,
                            right: box_left + box_w + 20,
                            bottom: box_top + box_h + 36,
                        };
                        DrawTextW(hdc, qr_sub.as_ptr(), -1, &mut rc_qs, DT_CENTER | DT_SINGLELINE);
                    }
                    DeleteObject(hfont_qr_caption as *mut c_void);
                }
            }

            // 3. Connected Devices Card
            let dev_brush = CreateSolidBrush(COLOR_CARD);
            let dev_pen = CreatePen(0, 1, COLOR_CARD_BORDER);
            let old_b = SelectObject(hdc, dev_brush as *mut c_void);
            let old_p = SelectObject(hdc, dev_pen);

            RoundRect(hdc, 35, 330, 605, 450, 12, 12);

            SelectObject(hdc, old_b);
            SelectObject(hdc, old_p);
            DeleteObject(dev_brush as *mut c_void);
            DeleteObject(dev_pen);

            SelectObject(hdc, hfont_info as *mut c_void);
            SetTextColor(hdc, COLOR_TEXT_WHITE);

            let dev_header = to_wide("Connected Mobile Devices:");
            let mut rc_dh = RECT { left: 55, top: 345, right: 585, bottom: 370 };
            DrawTextW(hdc, dev_header.as_ptr(), -1, &mut rc_dh, DT_LEFT | DT_SINGLELINE);

            SelectObject(hdc, hfont_sub as *mut c_void);
            if let Some(ref state) = GLOBAL_STATE {
                let clients_guard = state.clients.lock().unwrap();
                if clients_guard.is_empty() {
                    SetTextColor(hdc, COLOR_TEXT_MUTED);
                    let none_text = to_wide("No device connected. Point mobile camera at QR code above to connect.");
                    let mut rc_dn = RECT { left: 55, top: 380, right: 585, bottom: 410 };
                    DrawTextW(hdc, none_text.as_ptr(), -1, &mut rc_dn, DT_LEFT | DT_SINGLELINE);
                } else {
                    let mut y_offset = 380;
                    for client in clients_guard.values().take(2) {
                        SetTextColor(hdc, COLOR_GREEN);
                        let c_text = to_wide(&format!("📱 {} ({})", client.name, client.ip));
                        let mut rc_c = RECT { left: 55, top: y_offset, right: 410, bottom: y_offset + 22 };
                        DrawTextW(hdc, c_text.as_ptr(), -1, &mut rc_c, DT_LEFT | DT_SINGLELINE | 0x00000004 /* DT_VCENTER */);

                        // Disconnect pill button
                        let hbrush_disc = CreateSolidBrush(COLOR_BTN_DISC);
                        let mut rc_disc = RECT { left: 418, top: y_offset, right: 494, bottom: y_offset + 22 };
                        FillRect(hdc, &rc_disc, hbrush_disc);
                        DeleteObject(hbrush_disc as *mut c_void);
                        SetTextColor(hdc, COLOR_CYAN);
                        let txt_disc = to_wide("Disconnect");
                        DrawTextW(hdc, txt_disc.as_ptr(), -1, &mut rc_disc, DT_CENTER | DT_SINGLELINE | 0x00000004 /* DT_VCENTER */);

                        // Remove pill button
                        let hbrush_rem = CreateSolidBrush(COLOR_BTN_REM);
                        let mut rc_rem = RECT { left: 504, top: y_offset, right: 574, bottom: y_offset + 22 };
                        FillRect(hdc, &rc_rem, hbrush_rem);
                        DeleteObject(hbrush_rem as *mut c_void);
                        SetTextColor(hdc, COLOR_RED);
                        let txt_rem = to_wide("Remove");
                        DrawTextW(hdc, txt_rem.as_ptr(), -1, &mut rc_rem, DT_CENTER | DT_SINGLELINE | 0x00000004 /* DT_VCENTER */);

                        y_offset += 26;
                    }
                }
            }

            // Bottom left hint
            SetTextColor(hdc, COLOR_TEXT_MUTED);
            let hint_text = to_wide("⚡ Touchscreen • Touchpad • Voice • Shortcuts Ready");
            let mut rc_hint = RECT { left: 35, top: 478, right: 330, bottom: 504 };
            DrawTextW(hdc, hint_text.as_ptr(), -1, &mut rc_hint, DT_LEFT | DT_SINGLELINE);

            // Cleanup GDI objects
            SelectObject(hdc, old_font);
            DeleteObject(hfont_title as *mut c_void);
            DeleteObject(hfont_sub as *mut c_void);
            DeleteObject(hfont_status as *mut c_void);
            DeleteObject(hfont_info as *mut c_void);

            // Blit offscreen double buffer atomically to the screen DC
            BitBlt(hdc_paint, 0, 0, win_w, win_h, hdc, 0, 0, SRCCOPY);

            // Cleanup offscreen double buffer
            SelectObject(hdc, old_bmp);
            DeleteObject(mem_bmp as *mut c_void);
            DeleteDC(hdc);

            EndPaint(hwnd, &ps);
            0
        }
        WM_CLOSE => {
            // Minimize to system tray instead of exiting
            ShowWindow(hwnd, SW_HIDE);
            0
        }
        0x0202 /* WM_LBUTTONUP */ => {
            let x = (lparam & 0xFFFF) as i32;
            let y = ((lparam >> 16) & 0xFFFF) as i32;
            if let Some(ref state) = GLOBAL_STATE {
                let clients_guard = state.clients.lock().unwrap();
                let clients_list: Vec<(String, String)> = clients_guard.values().take(2).map(|c| (c.id.clone(), c.name.clone())).collect();
                drop(clients_guard);

                let mut y_offset = 380;
                for (id, name) in clients_list {
                    // Check Disconnect button: left 418..494, top y_offset..y_offset + 22
                    if x >= 418 && x <= 494 && y >= y_offset && y <= y_offset + 22 {
                        state.disconnect_client(&id);
                        InvalidateRect(hwnd, std::ptr::null(), 0);
                        break;
                    }
                    // Check Remove button: left 504..574, top y_offset..y_offset + 22
                    if x >= 504 && x <= 574 && y >= y_offset && y <= y_offset + 22 {
                        let confirm_msg = to_wide(&format!("Are you sure you want to permanently remove and revoke '{}'?\n\nThis will permanently delete authentication credentials on both PC and mobile device.\nRe-pairing will require fresh PIN approval.", name));
                        let confirm_title = to_wide("Confirm Device Removal");
                        let res = MessageBoxW(hwnd, confirm_msg.as_ptr(), confirm_title.as_ptr(), 0x00000004 /* MB_YESNO */ | 0x00000030 /* MB_ICONWARNING */ | 0x00000100 /* MB_DEFBUTTON2 */);
                        if res == 6 /* IDYES */ {
                            state.remove_and_revoke_client(&id);
                            InvalidateRect(hwnd, std::ptr::null(), 0);
                        }
                        break;
                    }
                    y_offset += 26;
                }
            }
            0
        }
        WM_TRAYICON => {
            let event = lparam as u32;
            if event == 0x0202 /* WM_LBUTTONUP */ {
                ShowWindow(hwnd, 1 /* SW_SHOWNORMAL */);
                ShowWindow(hwnd, SW_RESTORE);
                ShowWindow(hwnd, SW_SHOW);
                SetForegroundWindow(hwnd);
                BringWindowToTop(hwnd);
            } else if event == 0x0205 /* WM_RBUTTONUP */ {
                let mut pt = POINT { x: 0, y: 0 };
                GetCursorPos(&mut pt);

                let hmenu = CreatePopupMenu();
                let txt_show = to_wide("Open Mobile Kemo Dashboard");
                let txt_exit = to_wide("Exit Server");

                AppendMenuW(hmenu, 0, ID_TRAY_OPEN, txt_show.as_ptr());
                AppendMenuW(hmenu, 0x00000800 /* MF_SEPARATOR */, 0, std::ptr::null());

                // Connected devices submenu
                if let Some(ref state) = GLOBAL_STATE {
                    let clients_guard = state.clients.lock().unwrap();
                    let clients_vec: Vec<(String, String)> = clients_guard.values().take(4).map(|c| (c.id.clone(), c.name.clone())).collect();
                    drop(clients_guard);

                    if !clients_vec.is_empty() {
                        for (idx, (_id, name)) in clients_vec.iter().enumerate() {
                            let hsub = CreatePopupMenu();
                            let txt_d = to_wide("Disconnect");
                            let txt_r = to_wide("Remove & Revoke");
                            AppendMenuW(hsub, 0, ID_TRAY_DISC_BASE + idx, txt_d.as_ptr());
                            AppendMenuW(hsub, 0, ID_TRAY_REM_BASE + idx, txt_r.as_ptr());

                            let dev_title = to_wide(&format!("📱 {}", name));
                            AppendMenuW(hmenu, 0x00000010 /* MF_POPUP */, hsub as usize, dev_title.as_ptr());
                        }
                        AppendMenuW(hmenu, 0x00000800 /* MF_SEPARATOR */, 0, std::ptr::null());
                    }
                }

                AppendMenuW(hmenu, 0, ID_TRAY_EXIT, txt_exit.as_ptr());

                SetForegroundWindow(hwnd);
                TrackPopupMenu(hmenu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, hwnd, std::ptr::null());
                DestroyMenu(hmenu);
            }
            0
        }
        WM_SHOW_WINDOW => {
            ShowWindow(hwnd, 1 /* SW_SHOWNORMAL */);
            ShowWindow(hwnd, SW_RESTORE);
            ShowWindow(hwnd, SW_SHOW);
            SetWindowPos(hwnd, (-1isize) as HWND, 0, 0, 0, 0, 0x0001 | 0x0002);
            SetWindowPos(hwnd, (-2isize) as HWND, 0, 0, 0, 0, 0x0001 | 0x0002);
            SetForegroundWindow(hwnd);
            BringWindowToTop(hwnd);
            0
        }
        WM_DESTROY => {
            remove_tray_icon(hwnd);
            #[cfg(target_os = "windows")]
            {
                use std::process::Command;
                let _ = Command::new("taskkill")
                    .args(&["/F", "/IM", "cloudflared.exe"])
                    .output();
            }
            PostQuitMessage(0);
            0
        }
        _ => DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

unsafe fn get_app_icon(h_inst: HINSTANCE) -> HICON {
    let ico_name1 = to_wide("icon.ico");
    let mut h_icon = LoadImageW(std::ptr::null_mut(), ico_name1.as_ptr(), IMAGE_ICON, 0, 0, LR_LOADFROMFILE | LR_DEFAULTSIZE) as HICON;
    if h_icon.is_null() {
        let ico_name2 = to_wide("C:\\bluetooth keyboard and mouse\\icon.ico");
        h_icon = LoadImageW(std::ptr::null_mut(), ico_name2.as_ptr(), IMAGE_ICON, 0, 0, LR_LOADFROMFILE | LR_DEFAULTSIZE) as HICON;
    }
    if h_icon.is_null() {
        h_icon = LoadIconW(h_inst, 1 as *const u16);
    }
    if h_icon.is_null() {
        h_icon = LoadIconW(std::ptr::null_mut(), 32512 as *const u16);
    }
    h_icon
}

unsafe fn add_tray_icon(hwnd: HWND, ip: &str, port: u16) {
    let mut nid: NOTIFYICONDATAW = std::mem::zeroed();
    nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
    nid.hWnd = hwnd;
    nid.uID = 1;
    nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_INFO;
    nid.uCallbackMessage = WM_TRAYICON;

    let h_inst = GetModuleHandleW(std::ptr::null());
    nid.hIcon = get_app_icon(h_inst);

    let tip = format!("Mobile Kemo ({}:{})", ip, port);
    let tip_w = to_wide(&tip);
    for (i, &c) in tip_w.iter().enumerate().take(127) {
        nid.szTip[i] = c;
    }

    let balloon_title = to_wide("Mobile Kemo Server Running");
    for (i, &c) in balloon_title.iter().enumerate().take(63) {
        nid.szInfoTitle[i] = c;
    }

    let balloon_info = to_wide(&format!("Connect from Android app using IP {}:{}", ip, port));
    for (i, &c) in balloon_info.iter().enumerate().take(255) {
        nid.szInfo[i] = c;
    }
    nid.dwInfoFlags = NIIF_INFO;

    Shell_NotifyIconW(NIM_ADD, &mut nid);
}

unsafe fn remove_tray_icon(hwnd: HWND) {
    let mut nid: NOTIFYICONDATAW = std::mem::zeroed();
    nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
    nid.hWnd = hwnd;
    nid.uID = 1;
    Shell_NotifyIconW(NIM_DELETE, &mut nid);
}

/// Spawns and runs the native Win32 GUI window on the calling thread.
/// Returns when the application is exited.
pub fn run_native_gui(state: Arc<AppState>) {
    unsafe {
        GLOBAL_STATE = Some(Arc::clone(&state));

        let h_inst = GetModuleHandleW(std::ptr::null());
        let class_name = to_wide("MobileKemoMainWindowClass");

        let mut wcx: WNDCLASSEXW = std::mem::zeroed();
        wcx.cbSize = std::mem::size_of::<WNDCLASSEXW>() as u32;
        wcx.style = 0x0003; // CS_HREDRAW | CS_VREDRAW
        wcx.lpfnWndProc = Some(window_proc);
        wcx.hInstance = h_inst;
        wcx.hCursor = LoadCursorW(std::ptr::null_mut(), 32512 as *const u16); // IDC_ARROW
        wcx.hbrBackground = CreateSolidBrush(COLOR_BG);
        wcx.lpszClassName = class_name.as_ptr();
        let h_icon = get_app_icon(h_inst);
        wcx.hIcon = h_icon;
        wcx.hIconSm = h_icon;

        RegisterClassExW(&wcx);

        // Center on screen
        let screen_w = GetSystemMetrics(0); // SM_CXSCREEN
        let screen_h = GetSystemMetrics(1); // SM_CYSCREEN
        let win_w = 650;
        let win_h = 560;
        let pos_x = (screen_w - win_w) / 2;
        let pos_y = (screen_h - win_h) / 2;

        let title = to_wide("Mobile Kemo - Wireless Keyboard, Mouse & Screen Server");

        let hwnd = CreateWindowExW(
            0,
            class_name.as_ptr(),
            title.as_ptr(),
            WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_VISIBLE,
            pos_x,
            pos_y,
            win_w,
            win_h,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            h_inst,
            std::ptr::null_mut(),
        );

        let _ = std::fs::write(
            "C:\\bluetooth keyboard and mouse\\window_created.log",
            format!("hwnd is_null: {}, err: {}\n", hwnd.is_null(), GetLastError()),
        );

        if hwnd.is_null() {
            eprintln!("[Mobile Kemo] Failed to create native Win32 window");
            return;
        }

        GLOBAL_HWND = hwnd;

        // Set high-resolution icon explicitly for the window and taskbar
        SendMessageW(hwnd, WM_SETICON, ICON_BIG, h_icon as LPARAM);
        SendMessageW(hwnd, WM_SETICON, ICON_SMALL, h_icon as LPARAM);

        // Allow any subsequent process to activate this window
        AllowSetForegroundWindow(0xFFFFFFFF);

        // Add System Tray Icon
        add_tray_icon(hwnd, &state.get_local_ip(), state.port);

        ShowWindow(hwnd, 1 /* SW_SHOWNORMAL */);
        ShowWindow(hwnd, SW_SHOW);
        UpdateWindow(hwnd);
        SetForegroundWindow(hwnd);
        BringWindowToTop(hwnd);

        let _ = std::fs::write(
            "C:\\bluetooth keyboard and mouse\\window_created.log",
            format!("HWND: {:?}, visible: true\n", hwnd),
        );

        // Standard Win32 Message Loop
        let mut msg: MSG = std::mem::zeroed();
        loop {
            let res = GetMessageW(&mut msg, std::ptr::null_mut(), 0, 0);
            if res <= 0 {
                let err = GetLastError();
                let _ = std::fs::write(
                    "C:\\bluetooth keyboard and mouse\\loop_exit.log",
                    format!("GetMessageW returned {}, last_err: {}\n", res, err),
                );
                break;
            }
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }
}

pub fn trigger_repaint() {
    unsafe {
        if !GLOBAL_HWND.is_null() && IsWindow(GLOBAL_HWND) != 0 {
            let mut rc = RECT { left: 0, top: 0, right: 0, bottom: 0 };
            GetClientRect(GLOBAL_HWND, &mut rc);
            InvalidateRect(GLOBAL_HWND, &rc, 0);
        }
    }
}
