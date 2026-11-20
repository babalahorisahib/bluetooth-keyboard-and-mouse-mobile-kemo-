#![windows_subsystem = "windows"]

#[cfg(target_os = "windows")]
extern "system" {
    fn CreateMutexW(lpMutexAttributes: *const std::ffi::c_void, bInitialOwner: i32, lpName: *const u16) -> *mut std::ffi::c_void;
    fn GetLastError() -> u32;
    fn CloseHandle(hObject: *mut std::ffi::c_void) -> i32;
    fn FindWindowW(lpClassName: *const u16, lpWindowName: *const u16) -> *mut std::ffi::c_void;
    fn PostMessageW(hWnd: *mut std::ffi::c_void, Msg: u32, wParam: usize, lParam: isize) -> i32;
    fn SetForegroundWindow(hWnd: *mut std::ffi::c_void) -> i32;
    fn ShowWindow(hWnd: *mut std::ffi::c_void, nCmdShow: i32) -> i32;
    fn SetWindowPos(hWnd: *mut std::ffi::c_void, hWndInsertAfter: *mut std::ffi::c_void, X: i32, Y: i32, cx: i32, cy: i32, uFlags: u32) -> i32;
    fn SetProcessDPIAware() -> i32;
    fn GetCurrentThreadId() -> u32;
    fn GetWindowThreadProcessId(hWnd: *mut std::ffi::c_void, lpdwProcessId: *mut u32) -> u32;
    fn AttachThreadInput(idAttach: u32, idAttachTo: u32, fAttach: i32) -> i32;
    fn BringWindowToTop(hWnd: *mut std::ffi::c_void) -> i32;
    fn IsHungAppWindow(hWnd: *mut std::ffi::c_void) -> i32;
}

#[cfg(target_os = "windows")]
fn ensure_windows_auto_start() {
    if let Ok(exe_path) = std::env::current_exe() {
        let exe_str = exe_path.to_string_lossy();
        let _ = std::process::Command::new("powershell")
            .args(&[
                "-NoProfile",
                "-Command",
                &format!("Set-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run' -Name 'MobileKemo' -Value '\"{}\"' -ErrorAction SilentlyContinue", exe_str),
            ])
            .output();
    }
}

fn main() {
    #[cfg(target_os = "windows")]
    unsafe {
        SetProcessDPIAware();
    }
    #[cfg(target_os = "windows")]
    ensure_windows_auto_start();

    let _ = std::fs::write("C:\\bluetooth keyboard and mouse\\trace.log", "step 1: main started\n");

    std::env::set_var("RUST_BACKTRACE", "1");
    let _ = std::fs::remove_file("C:\\bluetooth keyboard and mouse\\crash.log");
    let _ = std::fs::write("C:\\bluetooth keyboard and mouse\\run.log", "main() started\n");

    std::panic::set_hook(Box::new(|info| {
        let backtrace = std::backtrace::Backtrace::force_capture();
        let msg = format!("PANIC: {}\nLocation: {:?}\nBacktrace:\n{:?}", info, info.location(), backtrace);
        let _ = std::fs::write("C:\\bluetooth keyboard and mouse\\crash.log", msg);
    }));

    #[cfg(target_os = "windows")]
    let _mutex = {
        use std::ffi::OsStr;
        use std::os::windows::ffi::OsStrExt;

        let name: Vec<u16> = OsStr::new("Local\\MobileKemoDesktopSingleInstanceMutex")
            .encode_wide()
            .chain(std::iter::once(0))
            .collect();

        let handle = unsafe { CreateMutexW(std::ptr::null(), 1, name.as_ptr()) };
        let err = unsafe { GetLastError() };

        let _ = std::fs::write(
            "C:\\bluetooth keyboard and mouse\\mutex.log",
            format!("handle is_null: {}, err: {}\n", handle.is_null(), err),
        );

        // Check if an existing GUI window is running
        let class_name: Vec<u16> = OsStr::new("MobileKemoMainWindowClass")
            .encode_wide()
            .chain(std::iter::once(0))
            .collect();
        let hwnd = unsafe { FindWindowW(class_name.as_ptr(), std::ptr::null()) };
        if !hwnd.is_null() {
            let is_hung = unsafe { IsHungAppWindow(hwnd) != 0 };
            if is_hung {
                // If old instance is frozen, terminate it and allow new instance to launch
                let my_pid = std::process::id();
                let _ = std::process::Command::new("powershell")
                    .args(&[
                        "-NoProfile",
                        "-Command",
                        &format!("Get-Process -Name '*MobileKemo*' -ErrorAction SilentlyContinue | Where-Object {{ $_.Id -ne {} }} | Stop-Process -Force", my_pid),
                    ])
                    .output();
                std::thread::sleep(std::time::Duration::from_millis(400));
            } else {
                // Existing window healthy! Bring to front reliably across processes
                unsafe {
                    let cur_thread = GetCurrentThreadId();
                    let target_thread = GetWindowThreadProcessId(hwnd, std::ptr::null_mut());
                    if cur_thread != target_thread && target_thread != 0 {
                        AttachThreadInput(cur_thread, target_thread, 1);
                    }
                    ShowWindow(hwnd, 9 /* SW_RESTORE */);
                    ShowWindow(hwnd, 1 /* SW_SHOWNORMAL */);
                    ShowWindow(hwnd, 5 /* SW_SHOW */);
                    SetWindowPos(hwnd, (-1isize) as *mut std::ffi::c_void /* HWND_TOPMOST */, 0, 0, 0, 0, 0x0001 | 0x0002);
                    SetWindowPos(hwnd, (-2isize) as *mut std::ffi::c_void /* HWND_NOTOPMOST */, 0, 0, 0, 0, 0x0001 | 0x0002);
                    SetForegroundWindow(hwnd);
                    BringWindowToTop(hwnd);
                    if cur_thread != target_thread && target_thread != 0 {
                        AttachThreadInput(cur_thread, target_thread, 0);
                    }
                    PostMessageW(hwnd, 0x0400 + 102 /* WM_SHOW_WINDOW */, 0, 0);
                }
                let _ = std::fs::write(
                    "C:\\bluetooth keyboard and mouse\\exit_reason.log",
                    "Existing instance running; focused window and exited second instance\n",
                );
                return;
            }
        } else if !handle.is_null() && err == 183 {
            // Mutex exists but NO GUI window found (orphaned/headless background zombie holding port 58921).
            // Terminate other instances so THIS instance can display the window to the user cleanly.
            let my_pid = std::process::id();
            let _ = std::process::Command::new("powershell")
                .args(&[
                    "-NoProfile",
                    "-Command",
                    &format!("Get-Process -Name '*MobileKemo*' -ErrorAction SilentlyContinue | Where-Object {{ $_.Id -ne {} }} | Stop-Process -Force", my_pid),
                ])
                .output();
            std::thread::sleep(std::time::Duration::from_millis(300));
        }
        handle
    };

    let _ = std::fs::OpenOptions::new().append(true).open("C:\\bluetooth keyboard and mouse\\trace.log").map(|mut f| {
        use std::io::Write;
        let _ = writeln!(f, "step 3: mutex done");
    });

    // Start core WebSocket server and input/streaming engine immediately in dedicated runtime
    let port = 58921;
    let ip_str = local_ip_address::local_ip()
        .map(|ip| ip.to_string())
        .unwrap_or_else(|_| "127.0.0.1".to_string());

    let _ = std::fs::OpenOptions::new().append(true).open("C:\\bluetooth keyboard and mouse\\trace.log").map(|mut f| {
        use std::io::Write;
        let _ = writeln!(f, "step 4: ip {}", ip_str);
    });

    let app_state = std::sync::Arc::new(keylink_desktop_lib::AppState::new(ip_str.clone(), port));
    let input_engine = std::sync::Arc::new(keylink_desktop_lib::platform::InputEngine::new());

    let _ = std::fs::OpenOptions::new().append(true).open("C:\\bluetooth keyboard and mouse\\trace.log").map(|mut f| {
        use std::io::Write;
        let _ = writeln!(f, "step 5: input engine created");
    });

    // Start mDNS advertisement in background thread
    let server_name_mdns = app_state.server_name.clone();
    let ip_str_mdns = ip_str.clone();
    std::thread::Builder::new()
        .name("mobilekemo-mdns".into())
        .spawn(move || {
            let mut mdns = keylink_desktop_lib::network::MdnsBroadcaster::new();
            mdns.start(&server_name_mdns, port, &ip_str_mdns);
        })
        .ok();

    let _ = std::fs::OpenOptions::new().append(true).open("C:\\bluetooth keyboard and mouse\\trace.log").map(|mut f| {
        use std::io::Write;
        let _ = writeln!(f, "step 6: mdns thread spawned");
    });

    let state_for_server = std::sync::Arc::clone(&app_state);
    let engine_for_server = std::sync::Arc::clone(&input_engine);
    let auth = std::sync::Arc::clone(&state_for_server.auth_manager);

    std::thread::Builder::new()
        .name("mobilekemo-core-server".into())
        .spawn(move || {
            let rt = tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
                .expect("failed to create tokio runtime");
            rt.block_on(async move {
                keylink_desktop_lib::network::start_websocket_server(
                    port,
                    engine_for_server,
                    auth,
                    state_for_server,
                    None,
                )
                .await;
            });
        })
        .expect("failed to spawn server thread");

    let _ = std::fs::OpenOptions::new().append(true).open("C:\\bluetooth keyboard and mouse\\trace.log").map(|mut f| {
        use std::io::Write;
        let _ = writeln!(f, "step 7: server thread spawned, starting Cloudflare Tunnel");
    });

    // Start Cloudflare Tunnel supervisor for cross-network (4G / different network) access
    let state_for_tunnel = std::sync::Arc::clone(&app_state);
    std::thread::Builder::new()
        .name("mobilekemo-tunnel".into())
        .spawn(move || {
            let cloudflared_path = "C:\\bluetooth keyboard and mouse\\cloudflared.exe";
            if !std::path::Path::new(cloudflared_path).exists() {
                return;
            }
            use std::io::{BufRead, BufReader};
            use std::process::{Command, Stdio};

            #[cfg(target_os = "windows")]
            use std::os::windows::process::CommandExt;
            const CREATE_NO_WINDOW: u32 = 0x08000000;

            // Clean up old stale files and any leftover cloudflared instances
            let _ = std::fs::remove_file("C:\\bluetooth keyboard and mouse\\tunnel_active.txt");
            let _ = Command::new("taskkill")
                .args(&["/F", "/IM", "cloudflared.exe"])
                .output();

            loop {
                let mut cmd = Command::new(cloudflared_path);
                cmd.args(&[
                    "tunnel",
                    "--no-autoupdate",
                    "--protocol", "http2",
                    "--url", "http://127.0.0.1:58921"
                ])
                .stderr(Stdio::piped())
                .stdout(Stdio::null());
                #[cfg(target_os = "windows")]
                cmd.creation_flags(CREATE_NO_WINDOW);

                if let Ok(mut child) = cmd.spawn() {
                    let _ = std::fs::write("C:\\bluetooth keyboard and mouse\\cf_spawn.log", format!("cloudflared spawned with PID: {}\n", child.id()));
                    if let Some(stderr) = child.stderr.take() {
                        let reader = BufReader::new(stderr);
                        for line in reader.lines().flatten() {
                            let _ = std::fs::OpenOptions::new().create(true).append(true).open("C:\\bluetooth keyboard and mouse\\cf_live.log").map(|mut f| {
                                use std::io::Write;
                                let _ = writeln!(f, "{}", line);
                            });
                            if let Some(pos) = line.find(".trycloudflare.com") {
                                let prefix = &line[..pos + 18];
                                if let Some(start) = prefix.rfind("https://") {
                                    let url = &prefix[start..];
                                    if !url.contains("api.") && !url.contains("pkg.") && url.len() > 28 {
                                        state_for_tunnel.set_tunnel_url(url.to_string());
                                        let _ = std::fs::write("C:\\bluetooth keyboard and mouse\\tunnel_active.txt", url);
                                        #[cfg(target_os = "windows")]
                                        keylink_desktop_lib::native_gui::trigger_repaint();
                                    }
                                }
                            }
                        }
                    }
                    let status = child.wait();
                    let _ = std::fs::OpenOptions::new().create(true).append(true).open("C:\\bluetooth keyboard and mouse\\cf_spawn.log").map(|mut f| {
                        use std::io::Write;
                        let _ = writeln!(f, "cloudflared exited with status: {:?}\n", status);
                    });
                } else {
                    let _ = std::fs::write("C:\\bluetooth keyboard and mouse\\cf_spawn.log", "FAILED to spawn cloudflared\n");
                }
                std::thread::sleep(std::time::Duration::from_secs(3));
            }
        })
        .ok();

    // Autonomous Tunnel Health Watchdog: Continuously probes active tunnel URL and recycles cloudflared.exe if Cloudflare edge drops
    let watchdog_state = std::sync::Arc::clone(&app_state);
    std::thread::Builder::new()
        .name("mobilekemo-tunnel-watchdog".into())
        .spawn(move || {
            let mut consecutive_failures = 0;
            // Wait 30 seconds on startup for cloudflared to acquire initial tunnel
            std::thread::sleep(std::time::Duration::from_secs(30));
            loop {
                let cur_tunnel = watchdog_state.get_tunnel_url();
                if !cur_tunnel.is_empty() {
                    let clean_url = cur_tunnel.trim();
                    let is_healthy = {
                        #[cfg(target_os = "windows")]
                        {
                            use std::process::Command;
                            use std::os::windows::process::CommandExt;
                            const CREATE_NO_WINDOW: u32 = 0x08000000;
                            let mut probe = Command::new("curl.exe");
                            // Generous 12s timeout, fetch HTTP status code without -f so 200/400/426 are recognized as reachable
                            probe.args(&["--ssl-no-revoke", "-s", "-m", "12", "-o", "NUL", "-w", "%{http_code}", clean_url]);
                            probe.creation_flags(CREATE_NO_WINDOW);
                            probe.output().map(|o| {
                                let code = String::from_utf8_lossy(&o.stdout).trim().to_string();
                                code == "200" || code == "400" || code == "426" || code == "301" || code == "302"
                            }).unwrap_or(false)
                        }
                        #[cfg(not(target_os = "windows"))]
                        {
                            false
                        }
                    };

                    if is_healthy {
                        consecutive_failures = 0;
                    } else {
                        consecutive_failures += 1;
                        if consecutive_failures >= 4 {
                            // Tunnel confirmed dead for 4 consecutive checks (> 3 minutes). Recycle cloudflared!
                            #[cfg(target_os = "windows")]
                            {
                                use std::process::Command;
                                let _ = Command::new("taskkill")
                                    .args(&["/F", "/IM", "cloudflared.exe"])
                                    .output();
                            }
                            watchdog_state.set_tunnel_url(String::new());
                            let _ = std::fs::remove_file("C:\\bluetooth keyboard and mouse\\tunnel_active.txt");
                            consecutive_failures = 0;
                            std::thread::sleep(std::time::Duration::from_secs(10));
                        }
                    }
                }
                std::thread::sleep(std::time::Duration::from_secs(45));
            }
        })
        .ok();

    // Universal Presence Synchronization Thread (Local UDP Discovery + Cloud Relay Rendezvous)
    let sync_state = std::sync::Arc::clone(&app_state);
    std::thread::Builder::new()
        .name("mobilekemo-presence-sync".into())
        .spawn(move || {
            // 1. Spawn local UDP Discovery responder on port 58922
            let udp_state = std::sync::Arc::clone(&sync_state);
            std::thread::spawn(move || {
                if let Ok(socket) = std::net::UdpSocket::bind("0.0.0.0:58922") {
                    let mut buf = [0u8; 512];
                    while let Ok((len, src)) = socket.recv_from(&mut buf) {
                        let req = String::from_utf8_lossy(&buf[..len]);
                        if req.contains("DISCOVER_KEMO") {
                            let resp = format!(
                                r#"{{"name":"{}","ip":"{}","port":{},"tunnel":"{}"}}"#,
                                udp_state.server_name,
                                udp_state.get_local_ip(),
                                udp_state.port,
                                udp_state.get_tunnel_url()
                            );
                            let _ = socket.send_to(resp.as_bytes(), src);
                        }
                    }
                }
            });

            // 2. Periodic Cloud Relay Presence publisher (ntfy.sh rendezvous)
            use sha2::{Sha256, Digest};
            let pin = sync_state.auth_manager.get_pin();
            let sanitized_name: String = sync_state.server_name
                .to_lowercase()
                .chars()
                .filter(|c| c.is_alphanumeric())
                .collect();

            // Derive secure unguessable presence topic using SHA-256 of server name and PIN
            let hash_input = format!("kemo_rendezvous:{}:{}", sanitized_name, pin);
            let mut hasher = Sha256::new();
            hasher.update(hash_input.as_bytes());
            let hash_hex = format!("{:x}", hasher.finalize());
            let secure_topic = format!("kemo_v2_{}", &hash_hex[..20]);
            let legacy_topic = format!("kemo_sync_{}", sanitized_name);

            let mut last_published_tunnel = String::new();
            let mut last_published_ip = String::new();
            let mut last_publish_time = 0u64;

            loop {
                let cur_tunnel = sync_state.get_tunnel_url();
                let clean_tunnel = cur_tunnel.trim_start_matches("https://").trim_start_matches("http://");
                let cur_ip = sync_state.get_local_ip();
                let now_ts = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_secs();

                let tunnel_changed = clean_tunnel != last_published_tunnel && !clean_tunnel.is_empty();
                let ip_changed = cur_ip != last_published_ip && !cur_ip.is_empty();
                let heartbeat_due = now_ts.saturating_sub(last_publish_time) >= 600; // 10 min heartbeat to prevent quota exhaustion

                if ip_changed && !last_published_ip.is_empty() {
                    // Physical network adapter changed! Restart cloudflared to bind to new network route immediately
                    #[cfg(target_os = "windows")]
                    {
                        use std::process::Command;
                        let _ = Command::new("taskkill")
                            .args(&["/F", "/IM", "cloudflared.exe"])
                            .output();
                    }
                    last_published_tunnel.clear();
                }

                if (tunnel_changed || ip_changed || heartbeat_due) && !clean_tunnel.is_empty() {
                    // Secure payload: NEVER publish PIN, credentials, or session tokens to public internet!
                    let payload = format!(
                        r#"{{"name":"{}","ip":"{}","port":{},"tunnel":"{}","ts":{}}}"#,
                        sync_state.server_name, cur_ip, sync_state.port, clean_tunnel, now_ts
                    );

                    #[cfg(target_os = "windows")]
                    {
                        use std::process::Command;
                        #[cfg(target_os = "windows")]
                        use std::os::windows::process::CommandExt;
                        const CREATE_NO_WINDOW: u32 = 0x08000000;

                        // Publish to secure rendezvous topic
                        let sec_url = format!("https://ntfy.sh/{}", secure_topic);
                        let mut cmd1 = Command::new("curl.exe");
                        cmd1.args(&["--ssl-no-revoke", "-s", "-m", "15", "-X", "POST", "-d", &payload, &sec_url]);
                        cmd1.creation_flags(CREATE_NO_WINDOW);
                        let _ = cmd1.output();

                        // Also update legacy topic (without credentials) for backwards compatibility
                        let leg_url = format!("https://ntfy.sh/{}", legacy_topic);
                        let mut cmd2 = Command::new("curl.exe");
                        cmd2.args(&["--ssl-no-revoke", "-s", "-m", "15", "-X", "POST", "-d", &payload, &leg_url]);
                        cmd2.creation_flags(CREATE_NO_WINDOW);
                        let _ = cmd2.output();
                    }

                    last_published_tunnel = clean_tunnel.to_string();
                    last_published_ip = cur_ip.to_string();
                    last_publish_time = now_ts;
                }

                std::thread::sleep(std::time::Duration::from_secs(5));
            }
        })
        .ok();

    let _ = std::fs::OpenOptions::new().append(true).open("C:\\bluetooth keyboard and mouse\\trace.log").map(|mut f| {
        use std::io::Write;
        let _ = writeln!(f, "step 8: calling run_native_gui");
    });

    #[cfg(target_os = "windows")]
    keylink_desktop_lib::native_gui::run_native_gui(std::sync::Arc::clone(&app_state));

    #[cfg(not(target_os = "windows"))]
    keylink_desktop_lib::run();

    #[cfg(target_os = "windows")]
    unsafe {
        if !_mutex.is_null() {
            CloseHandle(_mutex);
        }
        let _ = std::process::Command::new("taskkill")
            .args(&["/F", "/IM", "cloudflared.exe"])
            .output();
    }
}
