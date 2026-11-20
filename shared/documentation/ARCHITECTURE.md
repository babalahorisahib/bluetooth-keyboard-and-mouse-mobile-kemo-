# KeyLink System Architecture

## Overview
KeyLink is designed with a layered, decoupled architecture allowing identical input control logic across multiple transport layers (Wi-Fi WebSocket in Phase 1, Bluetooth Low Energy GATT / Classic HID in Phase 2).

```
+-----------------------------------------------------------------------+
|                             MOBILE APP (Flutter)                     |
|                                                                       |
|  [ Dashboard ]   [ Wireless Keyboard ]   [ Touchpad ]   [ Settings ]  |
|         │                  │                  │               │       |
|         ▼                  ▼                  ▼               ▼       |
|  +─────────────────────────────────────────────────────────────────+  |
|  |                    Input & Command Generation                   |  |
|  +─────────────────────────────────────────────────────────────────+  |
|                                    │                                  |
|                                    ▼                                  |
|  +─────────────────────────────────────────────────────────────────+  |
|  |                  Transport Interface (Abstract)                 |  |
|  |             - connect(), send(), disconnect(), stream           |  |
|  +─────────────────────────────────────────────────────────────────+  |
|            │                                              │           |
|            ▼ (Phase 1: Active)                            ▼ (Phase 2) |
|  [ WebSocketTransport ]                           [ BleTransport ]    |
|   - mDNS Discovery / QR Scanner                    - BLE GATT / HID   |
+────────────┼──────────────────────────────────────────────────────────+
             │ Wi-Fi LAN (WebSocket JSON, port 58921)
             ▼
+-----------------------------------------------------------------------+
|                           DESKTOP AGENT (Tauri 2 + Rust)              |
|                                                                       |
|  [ React / TS UI ] <───── Tauri IPC ─────> [ Rust Tauri Core ]        |
|  - QR Code Display                         - Settings & State Manager |
|  - Connected Devices                       - Security / Pairing Auth  |
|  - Sensitivity & Settings                  - System Tray Integration  |
|                                                        │              |
|                                                        ▼              |
|  +─────────────────────────────────────────────────────────────────+  |
|  |                  Transport Server (Abstract / Modular)          |  |
|  |  [ WebSocket Server (tokio-tungstenite) ]  [ Future BLE Listener]| |
|  +─────────────────────────────────────────────────────────────────+  |
|                                    │                                  |
|                                    ▼                                  |
|  +─────────────────────────────────────────────────────────────────+  |
|  |                    Protocol Dispatcher & Validator              |  |
|  |         - Parse KeyLinkMessage, Validate Pairing Token          |  |
|  +─────────────────────────────────────────────────────────────────+  |
|                                    │                                  |
|                                    ▼                                  |
|  +─────────────────────────────────────────────────────────────────+  |
|  |                       Native Input Engine                       |  |
|  |   ┌──────────────────────────────┬───────────────────────────┐  |  |
|  |   │     Windows Native Driver    │     macOS Native Driver   │  |  |
|  |   │   - SendInput API            │   - CoreGraphics CGEvent  │  |  |
|  |   │   - KEYEVENTF_UNICODE        │   - CGEventKeyboardSetUni │  |  |
|  |   │   - Relative mouse moves     │   - Accessibility Check   │  |  |
|  |   └──────────────────────────────┴───────────────────────────┘  |  |
|  +─────────────────────────────────────────────────────────────────+  |
+-----------------------------------------------------------------------+
```

## Key Invariants
1. **Transport Agnostic**: The input command parser and the native input drivers have no dependency on WebSockets or network sockets. They only accept typed `KeyLinkCommand` enums.
2. **Zero-Keylogging Security**: Typed characters are processed directly by operating system input injection without persisting keystrokes or logging sensitive text into log files.
3. **True Unicode Text Injection**: Unlike standard virtual-key drivers that fail on non-ASCII characters, KeyLink leverages Windows `KEYEVENTF_UNICODE` (UTF-16) and macOS `CGEventKeyboardSetUnicodeString`, ensuring flawless Urdu, Arabic, accented characters, and emojis without needing matching host keyboard layouts!
