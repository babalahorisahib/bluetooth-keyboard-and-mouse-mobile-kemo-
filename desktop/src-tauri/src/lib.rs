pub mod input;
pub mod network;
pub mod platform;
pub mod assistant;
#[cfg(target_os = "windows")]
pub mod native_gui;

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager};
use tauri::menu::{Menu, MenuItem};
use tauri::tray::{TrayIconBuilder, TrayIconEvent};
use local_ip_address::local_ip;

use network::{start_websocket_server, AuthManager, MdnsBroadcaster};
use platform::InputEngine;


#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectedClientInfo {
    pub id: String,
    pub name: String,
    pub ip: String,
    pub os: String,
    pub connected_at: String,
    pub last_ping_ms: i64,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ServerStateDto {
    pub running: bool,
    pub server_name: String,
    pub local_ip: String,
    pub port: u16,
    pub pin: String,
    pub qr_payload: String,
    pub connected_clients: Vec<ConnectedClientInfo>,
    pub os: String,
    pub accessibility_permission: bool,
}

pub struct AppState {
    pub server_name: String,
    pub local_ip: Mutex<String>,
    pub port: u16,
    pub tunnel_url: Mutex<String>,
    pub auth_manager: Arc<AuthManager>,
    pub clients: Mutex<HashMap<String, ConnectedClientInfo>>,
    pub client_senders: Mutex<HashMap<String, tokio::sync::mpsc::UnboundedSender<tokio_tungstenite::tungstenite::Message>>>,
}

impl AppState {
    pub fn new(local_ip: String, port: u16) -> Self {
        let hostname = std::env::var("COMPUTERNAME")
            .or_else(|_| std::env::var("HOSTNAME"))
            .unwrap_or_else(|_| "MobileKemo-PC".to_string());

        AppState {
            server_name: hostname,
            local_ip: Mutex::new(local_ip),
            port,
            tunnel_url: Mutex::new(String::new()),
            auth_manager: Arc::new(AuthManager::new()),
            clients: Mutex::new(HashMap::new()),
            client_senders: Mutex::new(HashMap::new()),
        }
    }

    pub fn get_local_ip(&self) -> String {
        if let Ok(ip) = local_ip_address::local_ip() {
            let s = ip.to_string();
            if s != "127.0.0.1" {
                *self.local_ip.lock().unwrap() = s.clone();
                return s;
            }
        }
        self.local_ip.lock().unwrap().clone()
    }

    pub fn set_local_ip(&self, ip: String) {
        *self.local_ip.lock().unwrap() = ip;
    }

    pub fn get_tunnel_url(&self) -> String {
        let mem = self.tunnel_url.lock().unwrap().clone();
        if !mem.is_empty() {
            return mem;
        }
        if let Ok(file_val) = std::fs::read_to_string("C:\\bluetooth keyboard and mouse\\tunnel_active.txt") {
            let trimmed = file_val.trim();
            if trimmed.starts_with("http") && trimmed.contains(".trycloudflare.com") {
                *self.tunnel_url.lock().unwrap() = trimmed.to_string();
                return trimmed.to_string();
            }
        }
        String::new()
    }

    pub fn set_tunnel_url(&self, url: String) {
        *self.tunnel_url.lock().unwrap() = url;
    }

    pub fn add_client(&self, id: &str, name: &str, ip: &str, os: &str) {
        let mut map = self.clients.lock().unwrap();
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        map.insert(
            id.to_string(),
            ConnectedClientInfo {
                id: id.to_string(),
                name: name.to_string(),
                ip: ip.to_string(),
                os: os.to_string(),
                connected_at: format!("{}s ago", now),
                last_ping_ms: 0,
            },
        );
    }

    pub fn update_client_ping(&self, id: &str, ping: i64) {
        let mut map = self.clients.lock().unwrap();
        if let Some(c) = map.get_mut(id) {
            c.last_ping_ms = ping;
        }
    }

    pub fn remove_client(&self, id: &str) {
        let mut map = self.clients.lock().unwrap();
        map.remove(id);
    }

    pub fn register_client_sender(&self, id: &str, sender: tokio::sync::mpsc::UnboundedSender<tokio_tungstenite::tungstenite::Message>) {
        let mut map = self.client_senders.lock().unwrap();
        map.insert(id.to_string(), sender);
    }

    pub fn unregister_client_sender(&self, id: &str) {
        let mut map = self.client_senders.lock().unwrap();
        map.remove(id);
    }

    pub fn disconnect_client(&self, client_id: &str) {
        let sender = {
            let senders = self.client_senders.lock().unwrap();
            senders.get(client_id).cloned()
        };
        if let Some(tx) = sender {
            let msg = serde_json::json!({
                "v": 1,
                "type": "SERVER_DISCONNECT",
                "payload": {
                    "reason": "disconnected_by_server"
                }
            });
            let _ = tx.send(tokio_tungstenite::tungstenite::Message::Text(msg.to_string()));
            let _ = tx.send(tokio_tungstenite::tungstenite::Message::Close(None));
        }
        self.remove_client(client_id);
        #[cfg(target_os = "windows")]
        crate::native_gui::request_gui_repaint();
    }

    pub fn remove_and_revoke_client(&self, client_id: &str) {
        let sender = {
            let senders = self.client_senders.lock().unwrap();
            senders.get(client_id).cloned()
        };
        if let Some(tx) = sender {
            let msg = serde_json::json!({
                "v": 1,
                "type": "DEVICE_REMOVED",
                "payload": {
                    "device_id": client_id,
                    "reason": "revoked_by_server"
                }
            });
            let _ = tx.send(tokio_tungstenite::tungstenite::Message::Text(msg.to_string()));
            let _ = tx.send(tokio_tungstenite::tungstenite::Message::Close(None));
        }
        self.auth_manager.revoke_device(client_id);
        self.remove_client(client_id);
        #[cfg(target_os = "windows")]
        crate::native_gui::request_gui_repaint();
    }

    pub fn get_state_dto(&self) -> ServerStateDto {
        let clients: Vec<ConnectedClientInfo> = self.clients.lock().unwrap().values().cloned().collect();
        let pin = self.auth_manager.get_pin();
        let cur_ip = local_ip()
            .map(|ip| ip.to_string())
            .unwrap_or_else(|_| self.get_local_ip());
        let qr = serde_json::json!({
            "ip": cur_ip,
            "port": self.port,
            "pin": pin,
            "name": self.server_name
        });

        #[cfg(target_os = "macos")]
        let has_perm = platform::macos::MacOsDriver::check_accessibility(false);
        #[cfg(not(target_os = "macos"))]
        let has_perm = true;

        ServerStateDto {
            running: true,
            server_name: self.server_name.clone(),
            local_ip: cur_ip,
            port: self.port,
            pin,
            qr_payload: qr.to_string(),
            connected_clients: clients,
            os: if cfg!(target_os = "macos") { "macos".into() } else { "windows".into() },
            accessibility_permission: has_perm,
        }
    }

    pub fn emit_update(&self, app: &AppHandle) {
        let _ = app.emit("server-state-update", self.get_state_dto());
    }
}

#[tauri::command]
fn get_server_state(state: tauri::State<Arc<AppState>>) -> ServerStateDto {
    state.get_state_dto()
}

#[tauri::command]
fn set_pin(pin: String, state: tauri::State<Arc<AppState>>, app: AppHandle) -> ServerStateDto {
    state.auth_manager.set_pin(pin);
    let dto = state.get_state_dto();
    state.emit_update(&app);
    dto
}

#[tauri::command]
fn disconnect_client(client_id: String, state: tauri::State<Arc<AppState>>, app: AppHandle) {
    state.auth_manager.revoke_device(&client_id);
    state.remove_client(&client_id);
    state.emit_update(&app);
}

#[tauri::command]
fn check_accessibility() -> bool {
    #[cfg(target_os = "macos")]
    {
        platform::macos::MacOsDriver::check_accessibility(true)
    }
    #[cfg(not(target_os = "macos"))]
    {
        true
    }
}


#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let port = 58921;
    let ip_str = local_ip()
        .map(|ip| ip.to_string())
        .unwrap_or_else(|_| "127.0.0.1".to_string());

    let app_state = Arc::new(AppState::new(ip_str.clone(), port));
    let input_engine = Arc::new(InputEngine::new());

    // Start mDNS advertisement in background
    let mut mdns = MdnsBroadcaster::new();
    mdns.start(&app_state.server_name, port, &ip_str);

    let state_for_server = Arc::clone(&app_state);
    let engine_for_server = Arc::clone(&input_engine);

    println!("[Mobile Kemo] Starting Mobile Kemo on {} port {}", ip_str, port);

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .manage(Arc::clone(&app_state))
        .on_window_event(|window, event| {
            let _ = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open("C:\\bluetooth keyboard and mouse\\window_events.log")
                .and_then(|mut f| {
                    use std::io::Write;
                    writeln!(f, "Window event: {:?}", event)
                });

            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .invoke_handler(tauri::generate_handler![
            get_server_state,
            set_pin,
            disconnect_client,
            check_accessibility
        ])
        .setup(move |app| {
            let handle = app.handle().clone();
            let auth = Arc::clone(&state_for_server.auth_manager);

            // Ensure main window is shown and unminimized
            if let Some(ref window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.unminimize();
            }

            // Setup System Tray Menu (always ensure an icon is available)
            let icon = app.default_window_icon().cloned()
                .or_else(|| tauri::image::Image::from_app_icon_resource(32).ok())
                .unwrap_or_else(|| tauri::image::Image::new_owned(vec![0u8; 32 * 32 * 4], 32, 32));

            if let (Ok(quit_i), Ok(show_i)) = (
                MenuItem::with_id(app, "quit", "Quit Mobile Kemo", true, None::<&str>),
                MenuItem::with_id(app, "show", "Open Mobile Kemo Dashboard", true, None::<&str>),
            ) {
                if let Ok(menu) = Menu::with_items(app, &[&show_i, &quit_i]) {
                    let tray_res = TrayIconBuilder::new()
                        .icon(icon)
                        .menu(&menu)
                        .tooltip("Mobile Kemo Server")
                        .on_menu_event(|app, event| {
                            match event.id.as_ref() {
                                "quit" => {
                                    app.exit(0);
                                }
                                "show" => {
                                    if let Some(window) = app.get_webview_window("main") {
                                        let _ = window.show();
                                        let _ = window.unminimize();
                                        let _ = window.set_focus();
                                    }
                                }
                                _ => {}
                            }
                        })
                        .on_tray_icon_event(|tray, event| {
                            if let TrayIconEvent::Click { .. } = event {
                                let app = tray.app_handle();
                                if let Some(window) = app.get_webview_window("main") {
                                    let _ = window.show();
                                    let _ = window.unminimize();
                                    let _ = window.set_focus();
                                }
                            }
                        })
                        .build(app);

                    let _ = std::fs::write("C:\\bluetooth keyboard and mouse\\tray_created.log", format!("tray_res: {:?}\n", tray_res.is_ok()));
                }
            }

            Ok(())
        })
        .build(tauri::generate_context!())
        .map_err(|e| {
            let msg = format!("TAURI BUILD ERROR: {:?}\n", e);
            let _ = std::fs::write("C:\\bluetooth keyboard and mouse\\crash.log", msg);
            e
        })
        .expect("error while building KeyLink desktop agent")
        .run(|_app_handle, event| {
            let _ = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open("C:\\bluetooth keyboard and mouse\\run_events.log")
                .and_then(|mut f| {
                    use std::io::Write;
                    writeln!(f, "Run event: {:?}", event)
                });
            if let tauri::RunEvent::ExitRequested { api, .. } = event {
                // Prevent app from exiting when windows are closed!
                api.prevent_exit();
            }
        });
}
