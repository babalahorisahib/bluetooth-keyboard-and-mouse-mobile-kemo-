# KeyLink Protocol Specification (v1.0)

## Overview
KeyLink uses a lightweight, structured JSON protocol designed to be **transport-agnostic**. The same protocol packets are sent over WebSockets in Phase 1 (Wi-Fi) and can be mapped directly to Bluetooth Low Energy (BLE) GATT characteristics or L2CAP channels in Phase 2.

## Envelope Format
Every message exchanged between mobile client and desktop agent adheres to this schema:

```json
{
  "v": 1,
  "type": "MESSAGE_TYPE",
  "id": "optional-uuid-or-seq",
  "payload": {}
}
```

---

## 1. Authentication & Pairing Messages

### `PAIR_REQUEST` (Mobile -> Desktop)
Initiates pairing approval when scanning a QR code or entering a pairing PIN.
```json
{
  "v": 1,
  "type": "PAIR_REQUEST",
  "payload": {
    "device_id": "c1f7a28e-3241-47fb-98e2-04db8038b7ef",
    "device_name": "Samsung Galaxy S23",
    "os": "Android 14",
    "pin": "489215"
  }
}
```

### `PAIR_RESPONSE` (Desktop -> Mobile)
Approval or denial of the pairing request.
```json
{
  "v": 1,
  "type": "PAIR_RESPONSE",
  "payload": {
    "status": "APPROVED", // "APPROVED" | "REJECTED" | "PIN_INVALID"
    "auth_token": "a82f349b1c784...",
    "server_name": "Workstation-Win11",
    "os": "windows", // "windows" | "macos"
    "screen_width": 2560,
    "screen_height": 1440
  }
}
```

### `AUTH_REQUEST` (Mobile -> Desktop)
Standard session authentication for previously paired devices.
```json
{
  "v": 1,
  "type": "AUTH_REQUEST",
  "payload": {
    "device_id": "c1f7a28e-3241-47fb-98e2-04db8038b7ef",
    "auth_token": "a82f349b1c784..."
  }
}
```

### `AUTH_RESPONSE` (Desktop -> Mobile)
```json
{
  "v": 1,
  "type": "AUTH_RESPONSE",
  "payload": {
    "status": "SUCCESS", // "SUCCESS" | "FAILED"
    "server_name": "Workstation-Win11",
    "os": "windows"
  }
}
```

---

## 2. Touchpad & Mouse Messages

### `MOUSE_MOVE` (Mobile -> Desktop)
Relative cursor displacement.
```json
{
  "v": 1,
  "type": "MOUSE_MOVE",
  "payload": {
    "dx": 14.5,
    "dy": -8.2
  }
}
```

### `MOUSE_CLICK` (Mobile -> Desktop)
Single, double, right, middle, or down/up events.
```json
{
  "v": 1,
  "type": "MOUSE_CLICK",
  "payload": {
    "button": "left", // "left" | "right" | "middle"
    "action": "click" // "click" | "double" | "down" | "up"
  }
}
```

### `MOUSE_SCROLL` (Mobile -> Desktop)
Vertical or horizontal scrolling.
```json
{
  "v": 1,
  "type": "MOUSE_SCROLL",
  "payload": {
    "dx": 0.0,
    "dy": -120.0
  }
}
```

---

## 3. Keyboard & Text Messages

### `TEXT_INPUT` (Mobile -> Desktop)
Sends raw Unicode text. Compatible with any language (English, Urdu, Arabic, Chinese, emojis, etc.).
```json
{
  "v": 1,
  "type": "TEXT_INPUT",
  "payload": {
    "text": "السلام علیکم KeyLink!"
  }
}
```

### `KEY_EVENT` (Mobile -> Desktop)
Key presses for navigation, functional keys, and control keys.
```json
{
  "v": 1,
  "type": "KEY_EVENT",
  "payload": {
    "key": "Backspace", // "Backspace" | "Enter" | "Tab" | "Space" | "ArrowUp" | "ArrowDown" | "ArrowLeft" | "ArrowRight" | "Escape" | "Delete" | "Home" | "End" | "PageUp" | "PageDown"
    "action": "press",   // "press" | "down" | "up"
    "modifiers": ["shift"] // optional: ["ctrl", "alt", "shift", "meta"]
  }
}
```

### `SHORTCUT` (Mobile -> Desktop)
System shortcuts.
```json
{
  "v": 1,
  "type": "SHORTCUT",
  "payload": {
    "action": "copy" // "copy" | "paste" | "cut" | "undo" | "redo" | "select_all" | "desktop" | "app_switcher" | "volume_up" | "volume_down" | "mute"
  }
}
```

---

## 4. Diagnostics & Health

### `PING` (Mobile -> Desktop)
```json
{
  "v": 1,
  "type": "PING",
  "payload": {
    "timestamp": 1729000000123
  }
}
```

### `PONG` (Desktop -> Mobile)
```json
{
  "v": 1,
  "type": "PONG",
  "payload": {
    "client_timestamp": 1729000000123,
    "server_timestamp": 1729000000128
  }
}
```

### `DISCONNECT` (Either direction)
```json
{
  "v": 1,
  "type": "DISCONNECT",
  "payload": {
    "reason": "emergency" // "user_logout" | "emergency" | "timeout"
  }
}
```
