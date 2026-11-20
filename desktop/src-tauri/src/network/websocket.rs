use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::net::TcpListener;
use tokio::sync::mpsc;
use tokio_tungstenite::accept_async;
use tokio_tungstenite::tungstenite::Message;
use futures_util::{SinkExt, StreamExt};
use serde_json::json;
use tauri::Manager;

use crate::input::{InputCommand, WireMessage};
use crate::platform::InputEngine;
use crate::network::auth::AuthManager;
use crate::AppState;

fn log_debug(msg: &str) {
    use std::io::Write;
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open("C:\\bluetooth keyboard and mouse\\server_debug.log") {
        let ts = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis()).unwrap_or(0);
        let _ = writeln!(f, "[{}] [WS] {}", ts, msg);
    }
}

async fn handle_http_request(mut stream: tokio::net::TcpStream, path: &str) {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    // If path is for APK download (e.g. /MobileKemo.apk, /apk, /download)
    if path.contains("MobileKemo.apk") || path.contains("/apk") || path.contains("/download") {
        let apk_path = "C:\\bluetooth keyboard and mouse\\MobileKemo.apk";
        if let Ok(bytes) = tokio::fs::read(apk_path).await {
            let resp = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/vnd.android.package-archive\r\nContent-Length: {}\r\nContent-Disposition: attachment; filename=\"MobileKemo.apk\"\r\nConnection: close\r\n\r\n",
                bytes.len()
            );
            let _ = stream.write_all(resp.as_bytes()).await;
            let _ = stream.write_all(&bytes).await;
            let _ = stream.flush().await;
            return;
        }
    }

    // Modern HTML landing page for browser downloads
    let html = r#"<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MobileKemo APK Download</title>
<style>
body { background: #0b0f19; color: #fff; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; margin: 0; padding: 16px; box-sizing: border-box; }
.card { background: #151b2b; padding: 36px 28px; border-radius: 20px; box-shadow: 0 10px 40px rgba(0,0,0,0.6); text-align: center; max-width: 400px; width: 100%; border: 1px solid #2a344d; }
h1 { font-size: 26px; margin: 0 0 10px 0; color: #38bdf8; font-weight: 800; letter-spacing: 0.5px; }
p { color: #94a3b8; font-size: 14px; margin: 0 0 28px 0; line-height: 1.5; }
.btn { display: block; background: linear-gradient(135deg, #0284c7, #2563eb); color: #fff; font-weight: 700; text-decoration: none; padding: 16px 24px; border-radius: 12px; font-size: 16px; box-shadow: 0 4px 16px rgba(37,99,235,0.4); }
.badge { display: inline-block; background: #1e293b; color: #38bdf8; padding: 4px 10px; border-radius: 999px; font-size: 11px; margin-bottom: 16px; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; }
</style>
</head>
<body>
<div class="card">
  <div class="badge">Official Mobile Build</div>
  <h1>MobileKemo</h1>
  <p>Universal Remote PC Controller<br>Wireless Keyboard &bull; Mouse &bull; Live Screen</p>
  <a class="btn" href="/MobileKemo.apk">Download MobileKemo.apk</a>
</div>
</body>
</html>"#;

    let resp = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        html.len(),
        html
    );
    let _ = stream.write_all(resp.as_bytes()).await;
    let _ = stream.flush().await;
}

pub async fn start_websocket_server(
    port: u16,
    input_engine: Arc<InputEngine>,
    auth_manager: Arc<AuthManager>,
    app_state: Arc<AppState>,
    app_handle: Option<tauri::AppHandle>,
) {
    let addr = format!("0.0.0.0:{}", port);
    let mut bind_attempts = 0;
    let listener = loop {
        match TcpListener::bind(&addr).await {
            Ok(l) => {
                let _ = std::fs::write("C:\\bluetooth keyboard and mouse\\server.log", format!("SUCCESS: bound to {}\n", addr));
                break l;
            }
            Err(e) => {
                bind_attempts += 1;
                if bind_attempts > 10 {
                    let _ = std::fs::write("C:\\bluetooth keyboard and mouse\\server.log", format!("FAILED to bind to {}: {:?}\n", addr, e));
                    return;
                }
                tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
            }
        }
    };

    println!("[Mobile Kemo] WebSocket server listening on {}", addr);

    while let Ok((stream, peer_addr)) = listener.accept().await {
        let _ = stream.set_nodelay(true);
        let input = Arc::clone(&input_engine);
        let auth = Arc::clone(&auth_manager);
        let state = Arc::clone(&app_state);
        let app = app_handle.clone();

        tokio::spawn(async move {
            let mut peek_buf = [0u8; 4096];
            let mut is_plain_http = false;
            let mut req_path = String::new();

            if let Ok(n) = stream.peek(&mut peek_buf).await {
                if n > 0 {
                    let text = String::from_utf8_lossy(&peek_buf[..n]);
                    let lower = text.to_lowercase();
                    // If it has WebSocket upgrade or key headers, it is definitely a WebSocket handshake!
                    if lower.contains("upgrade: websocket") || lower.contains("sec-websocket-key") {
                        is_plain_http = false;
                    } else if text.starts_with("GET ") || text.starts_with("HEAD ") {
                        is_plain_http = true;
                        if let Some(first_line) = text.lines().next() {
                            let parts: Vec<&str> = first_line.split_whitespace().collect();
                            if parts.len() >= 2 {
                                req_path = parts[1].to_string();
                            }
                        }
                    }
                }
            }

            if is_plain_http {
                handle_http_request(stream, &req_path).await;
                return;
            }

            let ws_stream = match accept_async(stream).await {
                Ok(s) => s,
                Err(e) => {
                    log_debug(&format!("WS accept error from {:?}: {:?}", peer_addr, e));
                    if peer_addr.ip().is_loopback() {
                        if let Some(ref a) = app {
                            if let Some(window) = a.get_webview_window("main") {
                                let _ = window.show();
                                let _ = window.unminimize();
                                let _ = window.set_focus();
                            }
                        }
                    }
                    return;
                }
            };

            let (mut ws_sender, mut ws_receiver) = ws_stream.split();
            let (out_tx, mut out_rx) = mpsc::unbounded_channel::<Message>();
            let (frame_tx, mut frame_rx) = tokio::sync::watch::channel::<Option<Vec<u8>>>(None);
            let (audio_tx, mut audio_rx) = mpsc::channel::<Vec<u8>>(100);

            let frame_in_flight = Arc::new(AtomicBool::new(false));
            let last_sent_ms = Arc::new(AtomicU64::new(0));

            let f_in_flight_w = Arc::clone(&frame_in_flight);
            let l_sent_ms_w = Arc::clone(&last_sent_ms);

            // Dedicated outbound writer task: Zero-Lag priority multiplexer
            let writer_handle = tokio::spawn(async move {
                loop {
                    tokio::select! {
                        biased;

                        // 1. Text control messages (Pair, Auth, Voice, PONG) take top priority
                        Some(msg) = out_rx.recv() => {
                            if ws_sender.send(msg).await.is_err() {
                                break;
                            }
                        }

                        // 2. Real-time audio stream (continuous low-latency system sound)
                        Some(audio_data) = audio_rx.recv() => {
                            if ws_sender.send(Message::Binary(audio_data)).await.is_err() {
                                break;
                            }
                        }

                        // 3. Real-time screen frame (Single slot: NEVER queues stale frames!)
                        res = frame_rx.changed() => {
                            if res.is_err() {
                                break;
                            }
                            let frame_opt = frame_rx.borrow_and_update().clone();
                            if let Some(jpeg) = frame_opt {
                                f_in_flight_w.store(true, Ordering::Release);
                                let now_ms = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0);
                                l_sent_ms_w.store(now_ms, Ordering::Release);
                                if ws_sender.send(Message::Binary(jpeg)).await.is_err() {
                                    break;
                                }
                            }
                        }
                    }
                }
            });

            #[cfg(target_os = "windows")]
            let mut audio_capturer = crate::platform::audio_capture::SystemAudioCapture::new();
            #[cfg(target_os = "windows")]
            let audio_player = crate::platform::audio_playback::SystemAudioPlayback::new();

            let mut authenticated = false;
            let mut client_id = String::new();
            let mut device_name = String::from("Mobile Client");
            let streaming_active = Arc::new(AtomicBool::new(false));
            let stream_generation = Arc::new(AtomicU64::new(0));

            while let Some(msg_res) = ws_receiver.next().await {
                let msg = match msg_res {
                    Ok(m) => m,
                    Err(_) => break,
                };

                if msg.is_close() {
                    break;
                }

                if let Message::Text(text) = msg {
                    if let Ok(wire) = serde_json::from_str::<WireMessage>(&text) {
                        match wire.r#type.as_str() {
                            "PAIR_REQUEST" => {
                                let dev_id = wire.payload.get("device_id").and_then(|v| v.as_str()).unwrap_or("");
                                let pin = wire.payload.get("pin").and_then(|v| v.as_str()).unwrap_or("");
                                let dev_name = wire.payload.get("device_name").and_then(|v| v.as_str()).unwrap_or("Phone");

                                if let Some(token) = auth.verify_pair_request(dev_id, pin) {
                                    authenticated = true;
                                    client_id = dev_id.to_string();
                                    device_name = dev_name.to_string();

                                    let resp = json!({
                                        "v": 1,
                                        "type": "PAIR_RESPONSE",
                                        "payload": {
                                            "status": "APPROVED",
                                            "auth_token": token,
                                            "server_name": state.server_name,
                                            "os": if cfg!(target_os = "macos") { "macos" } else { "windows" }
                                        }
                                    });
                                    let _ = out_tx.send(Message::Text(resp.to_string()));

                                    let client_display_ip = if peer_addr.ip().is_loopback() {
                                        "4G / Internet Relay".to_string()
                                    } else {
                                        peer_addr.ip().to_string()
                                    };
                                    state.add_client(&client_id, &device_name, &client_display_ip, "mobile");
                                    state.register_client_sender(&client_id, out_tx.clone());
                                    if let Some(ref a) = app {
                                        state.emit_update(a);
                                    }
                                    #[cfg(target_os = "windows")]
                                    crate::native_gui::request_gui_repaint();
                                } else {
                                    let resp = json!({
                                        "v": 1,
                                        "type": "PAIR_RESPONSE",
                                        "payload": { "status": "PIN_INVALID" }
                                    });
                                    let _ = out_tx.send(Message::Text(resp.to_string()));
                                    tokio::time::sleep(tokio::time::Duration::from_millis(150)).await;
                                    break;
                                }
                            }

                            "AUTH_REQUEST" => {
                                let dev_id = wire.payload.get("device_id").and_then(|v| v.as_str()).unwrap_or("");
                                let token = wire.payload.get("auth_token").and_then(|v| v.as_str()).unwrap_or("");

                                if auth.verify_auth_token(dev_id, token) {
                                    authenticated = true;
                                    client_id = dev_id.to_string();

                                    let resp = json!({
                                        "v": 1,
                                        "type": "AUTH_RESPONSE",
                                        "payload": {
                                            "status": "SUCCESS",
                                            "server_name": state.server_name,
                                            "os": if cfg!(target_os = "macos") { "macos" } else { "windows" }
                                        }
                                    });
                                    let _ = out_tx.send(Message::Text(resp.to_string()));

                                    let client_display_ip = if peer_addr.ip().is_loopback() {
                                        "4G / Internet Relay".to_string()
                                    } else {
                                        peer_addr.ip().to_string()
                                    };
                                    state.add_client(&client_id, &device_name, &client_display_ip, "mobile");
                                    state.register_client_sender(&client_id, out_tx.clone());
                                    if let Some(ref a) = app {
                                        state.emit_update(a);
                                    }
                                    #[cfg(target_os = "windows")]
                                    crate::native_gui::request_gui_repaint();
                                } else {
                                    let resp = json!({
                                        "v": 1,
                                        "type": "AUTH_RESPONSE",
                                        "payload": { "status": "FAILED" }
                                    });
                                    let _ = out_tx.send(Message::Text(resp.to_string()));
                                    tokio::time::sleep(tokio::time::Duration::from_millis(150)).await;
                                    break;
                                }
                            }

                            "PING" => {
                                let client_ts = wire.payload.get("timestamp").and_then(|v| v.as_i64()).unwrap_or(0);
                                let server_ts = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as i64;

                                if authenticated && !client_id.is_empty() {
                                    state.update_client_ping(&client_id, server_ts - client_ts);
                                }

                                let resp = json!({
                                    "v": 1,
                                    "type": "PONG",
                                    "payload": {
                                        "client_timestamp": client_ts,
                                        "server_timestamp": server_ts
                                    }
                                });
                                let _ = out_tx.send(Message::Text(resp.to_string()));
                            }

                            "FRAME_ACK" => {
                                frame_in_flight.store(false, Ordering::Release);
                            }

                            "REMOVE_DEVICE" => {
                                let dev_id = wire.payload.get("target_device_id")
                                    .or_else(|| wire.payload.get("device_id"))
                                    .and_then(|v| v.as_str())
                                    .unwrap_or(&client_id);
                                auth.revoke_device(dev_id);
                                let resp = json!({
                                    "v": 1,
                                    "type": "DEVICE_REMOVED",
                                    "payload": {
                                        "device_id": dev_id,
                                        "status": "REVOKED"
                                    }
                                });
                                let _ = out_tx.send(Message::Text(resp.to_string()));
                                state.remove_client(dev_id);
                                state.unregister_client_sender(dev_id);
                                if let Some(ref a) = app {
                                    state.emit_update(a);
                                }
                                #[cfg(target_os = "windows")]
                                crate::native_gui::request_gui_repaint();
                                tokio::time::sleep(tokio::time::Duration::from_millis(150)).await;
                                break;
                            }

                            "DISCONNECT" => {
                                break;
                            }

                            "SHOW_WINDOW" => {
                                if let Some(ref a) = app {
                                    if let Some(window) = a.get_webview_window("main") {
                                        let _ = window.show();
                                        let _ = window.unminimize();
                                        let _ = window.set_focus();
                                    }
                                }
                            }

                            _ => {
                                if !authenticated {
                                    log_debug(&format!("Ignored command '{}' from unauthenticated client", wire.r#type));
                                    continue;
                                }

                                match wire.to_command() {
                                    InputCommand::MouseMove { dx, dy } => {
                                        input.mouse_move(dx, dy);
                                    }
                                    InputCommand::MouseClick { button, action } => {
                                        log_debug(&format!("MouseClick: button={} action={}", button, action));
                                        input.mouse_click(&button, &action);
                                    }
                                    InputCommand::MouseScroll { dx, dy } => {
                                        input.mouse_scroll(dx, dy);
                                    }
                                    InputCommand::TextInput { text } => {
                                        log_debug(&format!("TextInput: \"{}\"", text));
                                        input.send_text(&text);
                                    }
                                    InputCommand::KeyEvent { key, action, modifiers } => {
                                        log_debug(&format!("KeyEvent: key={} action={} mods={:?}", key, action, modifiers));
                                        input.send_key(&key, &action, &modifiers);
                                    }
                                    InputCommand::Shortcut { action } => {
                                        log_debug(&format!("Shortcut: {}", action));
                                        input.send_shortcut(&action);
                                    }
                                    InputCommand::VoiceCommand { text, lang } => {
                                        log_debug(&format!("VoiceCommand: \"{}\"", text));
                                        let res = crate::assistant::execute_voice_command(&text, lang.as_deref(), &input);
                                        log_debug(&format!("VoiceResponse: success={} action={}", res.success, res.action));
                                        let resp = json!({
                                            "v": 1,
                                            "type": "VOICE_RESPONSE",
                                            "payload": {
                                                "success": res.success,
                                                "message": res.message,
                                                "action": res.action,
                                                "query": text
                                            }
                                        });
                                        let _ = out_tx.send(Message::Text(resp.to_string()));
                                    }
                                    InputCommand::ScreenStreamStart { quality, max_width, fps } => {
                                        input.reset_screen_cache();
                                        let current_gen = stream_generation.fetch_add(1, Ordering::SeqCst) + 1;
                                        streaming_active.store(true, Ordering::SeqCst);

                                        let is_active = Arc::clone(&streaming_active);
                                        let gen = Arc::clone(&stream_generation);
                                        let input_c = Arc::clone(&input);
                                        let f_tx = frame_tx.clone();
                                        let f_in_flight = Arc::clone(&frame_in_flight);
                                        let l_sent_ms = Arc::clone(&last_sent_ms);
                                        let target_fps = fps.clamp(8, 20);
                                        let interval_ms = (1000 / target_fps) as u64;
                                        let eff_width = max_width.min(1280);
                                        let eff_quality = quality.clamp(10, 75);

                                        tokio::spawn(async move {
                                            let mut interval = tokio::time::interval(tokio::time::Duration::from_millis(interval_ms));
                                            interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

                                            while gen.load(Ordering::Relaxed) == current_gen && is_active.load(Ordering::Relaxed) {
                                                interval.tick().await;
                                                if gen.load(Ordering::Relaxed) != current_gen || !is_active.load(Ordering::Relaxed) {
                                                    break;
                                                }

                                                // Zero-Bufferbloat Flow Control:
                                                if f_in_flight.load(Ordering::Acquire) {
                                                    let now_ms = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0);
                                                    let sent_time = l_sent_ms.load(Ordering::Acquire);
                                                    if now_ms.saturating_sub(sent_time) < 100 {
                                                        // Previous frame still in flight: skip capture tick to prevent bufferbloat
                                                        continue;
                                                    } else {
                                                        // Watchdog timeout (100ms) expired: unblock flight lock
                                                        f_in_flight.store(false, Ordering::Release);
                                                    }
                                                }

                                                let inp = Arc::clone(&input_c);
                                                let frame = tokio::task::spawn_blocking(move || {
                                                    inp.capture_screen(eff_width, eff_quality)
                                                }).await.ok().flatten();

                                                if let Some(jpeg) = frame {
                                                    if gen.load(Ordering::Relaxed) == current_gen && is_active.load(Ordering::Relaxed) {
                                                        let _ = f_tx.send(Some(jpeg));
                                                    }
                                                }
                                            }
                                        });
                                    }
                                    InputCommand::ScreenStreamStop => {
                                        stream_generation.fetch_add(1, Ordering::SeqCst);
                                        streaming_active.store(false, Ordering::SeqCst);
                                        let _ = frame_tx.send(None);
                                    }
                                    InputCommand::AudioStreamStart => {
                                        log_debug("AudioStreamStart received");
                                        #[cfg(target_os = "windows")]
                                        {
                                            audio_capturer.start(audio_tx.clone());
                                        }
                                    }
                                    InputCommand::AudioStreamStop => {
                                        log_debug("AudioStreamStop received");
                                        #[cfg(target_os = "windows")]
                                        {
                                            audio_capturer.stop();
                                        }
                                    }
                                    InputCommand::MicStreamStart => {
                                        log_debug("MicStreamStart received");
                                    }
                                    InputCommand::MicStreamStop => {
                                        log_debug("MicStreamStop received");
                                        #[cfg(target_os = "windows")]
                                        {
                                            audio_player.stop();
                                        }
                                    }
                                    InputCommand::TouchEvent { action, x, y } => {
                                        log_debug(&format!("TouchEvent: action={} ({:.3}, {:.3})", action, x, y));
                                        input.touch_event(&action, x, y);
                                    }
                                    InputCommand::Disconnect { .. } => {
                                        break;
                                    }
                                    _ => {}
                                }
                            }
                        }
                    }
                } else if let Message::Binary(bin) = msg {
                    if authenticated && bin.len() >= 12 && &bin[0..4] == b"KMIC" {
                        let channels = bin[5] as u16;
                        let sample_rate = u32::from_le_bytes([bin[6], bin[7], bin[8], bin[9]]);
                        let _seq = u16::from_le_bytes([bin[10], bin[11]]);
                        let pcm_data = bin[12..].to_vec();
                        #[cfg(target_os = "windows")]
                        audio_player.play_chunk(sample_rate, channels, pcm_data);
                    }
                }
            }

            streaming_active.store(false, Ordering::Relaxed);
            #[cfg(target_os = "windows")]
            {
                audio_capturer.stop();
                audio_player.stop();
            }
            writer_handle.abort();

            // Cleanup when disconnected
            if !client_id.is_empty() {
                state.unregister_client_sender(&client_id);
                state.remove_client(&client_id);
                if let Some(ref a) = app {
                    state.emit_update(a);
                }
                #[cfg(target_os = "windows")]
                crate::native_gui::request_gui_repaint();
            }
        });
    }
}
