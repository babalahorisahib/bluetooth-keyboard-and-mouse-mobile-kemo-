# KeyLink Bluetooth (Phase 2) Migration Plan

## 1. Abstract Transport Architecture
KeyLink decouples the input generation engine from the underlying transport layer.
Both mobile and desktop codebases isolate the transport behind an interface:

- **Mobile (Dart)**: `abstract class KeyLinkTransport` with `send(KeyLinkMessage message)`
- **Desktop (Rust)**: `pub trait TransportChannel` with `async fn handle_incoming(packet: &[u8])`

## 2. Bluetooth Modes
In Phase 2, two Bluetooth options are supported without rewriting input or touchpad logic:

### Option A: Custom BLE GATT Service (Fastest & Most Flexible)
- **Service UUID**: `0000FA01-0000-1000-8000-00805F9B34FB` (KeyLink Service)
- **Characteristic 1 (Input Stream)**: UUID `...-FA02` (Write without response) - accepts JSON / CBOR-encoded KeyLink packets (`MOUSE_MOVE`, `KEY_EVENT`, `TEXT_INPUT`).
- **Characteristic 2 (Pairing & Auth)**: UUID `...-FA03` (Write + Notify) - exchange pairing tokens and nonce.
- **Advantage**: Bypasses OS Bluetooth HID restrictions on iOS and Android; identical packet structure as Wi-Fi.

### Option B: Standard Bluetooth HID (Human Interface Device)
- Android 9+ supports `BluetoothHidDevice` API.
- Converts `KeyLinkMessage` directly into standard HID reports (Mouse report: 3-5 bytes; Keyboard report: 8 bytes).
- Computer sees phone as a standard Bluetooth hardware mouse/keyboard without requiring any desktop software if desired.

## 3. Switching Transports Seamlessly
In `Settings` or `Connection Selector`, the user can toggle between:
- `TransportMode.wifi` (Phase 1)
- `TransportMode.bluetooth` (Phase 2)
- `TransportMode.auto` (Failover: Wi-Fi -> BLE if LAN drops)

All UI screens (`TouchpadScreen`, `KeyboardScreen`) remain 100% unchanged.
