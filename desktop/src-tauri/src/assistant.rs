use std::path::{Path, PathBuf};
use std::process::Command;
use std::fs;
use crate::platform::InputEngine;

#[derive(Debug, Clone)]
pub struct VoiceExecutionResult {
    pub success: bool,
    pub message: String,
    pub action: String,
}

impl VoiceExecutionResult {
    pub fn ok(action: &str, message: impl Into<String>) -> Self {
        VoiceExecutionResult {
            success: true,
            message: message.into(),
            action: action.to_string(),
        }
    }

    pub fn err(message: impl Into<String>) -> Self {
        VoiceExecutionResult {
            success: false,
            message: message.into(),
            action: "error".to_string(),
        }
    }
}

/// Helper to get user's active Desktop directory (handling OneDrive redirection)
fn get_desktop_dir() -> PathBuf {
    if let Ok(profile) = std::env::var("USERPROFILE") {
        let onedrive_desktop = PathBuf::from(&profile).join("OneDrive").join("Desktop");
        if onedrive_desktop.exists() {
            return onedrive_desktop;
        }
        let normal_desktop = PathBuf::from(&profile).join("Desktop");
        if normal_desktop.exists() {
            return normal_desktop;
        }
        return PathBuf::from(profile);
    }
    PathBuf::from("C:\\")
}

/// Helper to get user's Downloads directory
fn get_downloads_dir() -> PathBuf {
    if let Ok(profile) = std::env::var("USERPROFILE") {
        let dl = PathBuf::from(&profile).join("Downloads");
        if dl.exists() {
            return dl;
        }
        return PathBuf::from(profile);
    }
    PathBuf::from("C:\\Downloads")
}

/// Helper to get user's Documents directory
fn get_documents_dir() -> PathBuf {
    if let Ok(profile) = std::env::var("USERPROFILE") {
        let onedrive_docs = PathBuf::from(&profile).join("OneDrive").join("Documents");
        if onedrive_docs.exists() {
            return onedrive_docs;
        }
        let normal_docs = PathBuf::from(&profile).join("Documents");
        if normal_docs.exists() {
            return normal_docs;
        }
        return PathBuf::from(profile);
    }
    PathBuf::from("C:\\Documents")
}

/// URL encode helper without external crates
fn url_encode(input: &str) -> String {
    let mut encoded = String::new();
    for byte in input.bytes() {
        match byte {
            b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                encoded.push(byte as char);
            }
            b' ' => encoded.push('+'),
            _ => {
                encoded.push_str(&format!("%{:02X}", byte));
            }
        }
    }
    encoded
}

/// Helper to extract folder name from natural language Urdu/English commands
fn extract_folder_name(raw: &str, lower: &str) -> Option<String> {
    let is_folder_req = (lower.contains("folder") || raw.contains("فولڈر"))
        && (lower.contains("banao")
            || lower.contains("create")
            || lower.contains("make")
            || lower.contains("new")
            || lower.contains("naya")
            || raw.contains("بناؤ")
            || raw.contains("نیا"));

    if !is_folder_req {
        return None;
    }

    let mut cleaned = lower.to_string();
    let words_to_remove = [
        "create a new folder named ",
        "create a new folder called ",
        "create new folder ",
        "create folder ",
        "make new folder ",
        "make a folder ",
        "make folder ",
        "new folder ",
        "naya folder banao ",
        "aik naya folder banao ",
        "ek naya folder banao ",
        "naya folder ",
        "folder bana do ",
        "folder banao ",
        "bana do ",
        "banao ",
        " banao",
        "folder ",
        " folder",
        "ka folder",
        "k folder",
        "ke folder",
        "ke naam se",
        "k naam sy",
        "ke naam sy",
        "k nam sy",
        "k nam se",
        "nam sy",
        "naam se",
        "desktop par",
        "desktop pe",
        "desktop",
        "aik ",
        "ek ",
        "please ",
        "plz ",
    ];

    for w in &words_to_remove {
        cleaned = cleaned.replace(w, " ");
    }

    let mut cleaned_raw = raw.to_string();
    let urdu_remove = ["نیا فولڈر بناؤ", "فولڈر بناؤ", "بناؤ", "فولڈر", "نیا", "ایک", "کے نام سے"];
    for w in &urdu_remove {
        cleaned_raw = cleaned_raw.replace(w, " ");
    }

    let final_name = if !cleaned.trim().is_empty() {
        cleaned.trim().to_string()
    } else if !cleaned_raw.trim().is_empty() {
        cleaned_raw.trim().to_string()
    } else {
        "New Folder".to_string()
    };

    Some(final_name.replace(['/', '\\', ':', '*', '?', '"', '<', '>', '|'], "_"))
}

/// Helper to extract file name from natural language Urdu/English commands
fn extract_file_name(raw: &str, lower: &str) -> Option<String> {
    let is_file_req = (lower.contains("file") || lower.contains("document") || raw.contains("فائل"))
        && (lower.contains("banao")
            || lower.contains("create")
            || lower.contains("make")
            || lower.contains("new")
            || lower.contains("naya")
            || raw.contains("بناؤ")
            || raw.contains("نیا"));

    if !is_file_req {
        return None;
    }

    let mut cleaned = lower.to_string();
    let words_to_remove = [
        "create a new file named ",
        "create new file ",
        "create file ",
        "make new file ",
        "make file ",
        "text file banao ",
        "text file ",
        "naya file banao ",
        "file bana do ",
        "file banao ",
        "bana do ",
        "banao ",
        " banao",
        "file ",
        " file",
        "ka file",
        "k file",
        "ke naam se",
        "k nam sy",
        "desktop par",
        "desktop pe",
        "aik ",
        "ek ",
        "please ",
    ];

    for w in &words_to_remove {
        cleaned = cleaned.replace(w, " ");
    }

    let mut final_name = if !cleaned.trim().is_empty() {
        cleaned.trim().to_string()
    } else {
        "New Document.txt".to_string()
    };

    if !final_name.contains('.') {
        final_name = format!("{}.txt", final_name);
    }

    Some(final_name.replace(['/', '\\', ':', '*', '?', '"', '<', '>', '|'], "_"))
}

/// Execute a voice or typed text command in Urdu, Roman Urdu, or English
pub fn execute_voice_command(
    raw_query: &str,
    _lang: Option<&str>,
    input: &InputEngine,
) -> VoiceExecutionResult {
    let raw = raw_query.trim();
    if raw.is_empty() {
        return VoiceExecutionResult::err("Empty command received");
    }

    let lower = raw.to_lowercase();

    // -------------------------------------------------------------
    // 1. TYPING COMMANDS (English, Roman Urdu, Urdu)
    // -------------------------------------------------------------
    let type_prefixes = [
        "type karo ",
        "yeh type karo ",
        "ye type karo ",
        "type ",
        "likho ",
        "likh do ",
        "ye likho ",
        "yeh likho ",
        "ٹائپ کرو ",
        "یہ ٹائپ کرو ",
        "لکھو ",
        "لکھ دو ",
    ];

    for prefix in &type_prefixes {
        if lower.starts_with(prefix) || raw.starts_with(prefix) {
            let text_to_type = &raw[prefix.len()..].trim();
            if !text_to_type.is_empty() {
                input.send_text(text_to_type);
                return VoiceExecutionResult::ok(
                    "type_text",
                    format!("✓ Typed: \"{}\"", text_to_type),
                );
            }
        }
    }

    // -------------------------------------------------------------
    // 2. THIS PC & COMPUTER EXPLORER (Critical User Request)
    // -------------------------------------------------------------
    if lower.contains("this pc")
        || lower.contains("my computer")
        || lower.contains("open computer")
        || lower.contains("computer kholo")
        || raw.contains("کمپیوٹر کھولو")
        || (lower.contains("explorer") && !lower.contains("internet explorer"))
        || lower.contains("file manager")
    {
        #[cfg(target_os = "windows")]
        {
            let _ = Command::new("cmd")
                .args(&["/c", "start", "", "explorer.exe", "shell:MyComputerFolder"])
                .spawn();
        }
        #[cfg(target_os = "macos")]
        {
            let _ = Command::new("open").arg("/").spawn();
        }
        return VoiceExecutionResult::ok("open_folder", "✓ This PC opened successfully");
    }

    // -------------------------------------------------------------
    // 3. FILE OPERATIONS: CREATE FOLDER (Desktop / New Directory)
    // -------------------------------------------------------------
    if let Some(folder_name) = extract_folder_name(raw, &lower) {
        let target_path = get_desktop_dir().join(&folder_name);
        match fs::create_dir_all(&target_path) {
            Ok(_) => {
                #[cfg(target_os = "windows")]
                let _ = Command::new("explorer.exe").arg(&target_path).spawn();

                return VoiceExecutionResult::ok(
                    "create_folder",
                    format!("✓ Folder \"{}\" created on Desktop", folder_name),
                );
            }
            Err(e) => {
                return VoiceExecutionResult::err(format!("Failed to create folder: {}", e));
            }
        }
    }

    // -------------------------------------------------------------
    // 4. FILE OPERATIONS: CREATE FILE
    // -------------------------------------------------------------
    if let Some(file_name) = extract_file_name(raw, &lower) {
        let target_path = get_desktop_dir().join(&file_name);
        match fs::File::create(&target_path) {
            Ok(_) => {
                #[cfg(target_os = "windows")]
                let _ = Command::new("cmd").args(&["/c", "start", "", target_path.to_str().unwrap_or("")]).spawn();

                return VoiceExecutionResult::ok(
                    "create_file",
                    format!("✓ File \"{}\" created and opened", file_name),
                );
            }
            Err(e) => {
                return VoiceExecutionResult::err(format!("Failed to create file: {}", e));
            }
        }
    }

    // -------------------------------------------------------------
    // 5. FILE OPERATIONS: SEARCH / FIND FILE
    // -------------------------------------------------------------
    let search_file_prefixes = [
        "search file ",
        "find file ",
        "find ",
        "dhoondo ",
        "file dhoondo ",
        "search karo ",
        "فائل ڈھونڈو ",
        "ڈھونڈو ",
    ];

    for prefix in &search_file_prefixes {
        if lower.starts_with(prefix) || raw.starts_with(prefix) {
            let query = raw[prefix.len()..].trim();
            if !query.is_empty() && !lower.contains("google") && !lower.contains("youtube") {
                // Search common user locations using PowerShell
                let search_locations = [
                    get_desktop_dir(),
                    get_downloads_dir(),
                    get_documents_dir(),
                    PathBuf::from("H:\\"),
                    PathBuf::from("C:\\"),
                ];

                let mut found_path: Option<PathBuf> = None;
                for loc in &search_locations {
                    if loc.exists() {
                        let search_cmd = format!(
                            "Get-ChildItem -Path '{}' -Filter '*{}*' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName",
                            loc.to_str().unwrap_or(""),
                            query
                        );
                        let output = Command::new("powershell")
                            .args(&["-NoProfile", "-Command", &search_cmd])
                            .output();

                        if let Ok(out) = output {
                            let res_str = String::from_utf8_lossy(&out.stdout).trim().to_string();
                            if !res_str.is_empty() && Path::new(&res_str).exists() {
                                found_path = Some(PathBuf::from(res_str));
                                break;
                            }
                        }
                    }
                }

                if let Some(p) = found_path {
                    let path_str = p.to_str().unwrap_or("");
                    #[cfg(target_os = "windows")]
                    let _ = Command::new("explorer.exe")
                        .args(&[format!("/select,\"{}\"", path_str)])
                        .spawn();

                    return VoiceExecutionResult::ok(
                        "find_file",
                        format!("✓ Found: {}", p.file_name().unwrap_or_default().to_string_lossy()),
                    );
                } else {
                    return VoiceExecutionResult::err(format!("No matching file found for \"{}\"", query));
                }
            }
        }
    }

    // -------------------------------------------------------------
    // 6. OPEN SPECIFIC DRIVES & SYSTEM FOLDERS
    // -------------------------------------------------------------
    if lower.contains("c drive") || lower.contains("drive c") || lower == "open c" {
        open_system_command("explorer.exe", &["C:\\"]);
        return VoiceExecutionResult::ok("open_folder", "✓ Local Disk (C:) opened");
    }

    if lower.contains("d drive") || lower.contains("drive d") || lower == "open d" {
        open_system_command("explorer.exe", &["D:\\"]);
        return VoiceExecutionResult::ok("open_folder", "✓ Local Disk (D:) opened");
    }

    if lower.contains("h drive") || lower.contains("drive h") || lower == "open h" {
        open_system_command("explorer.exe", &["H:\\"]);
        return VoiceExecutionResult::ok("open_folder", "✓ Local Disk (H:) opened");
    }

    if lower.contains("download") || raw.contains("ڈاؤنلوڈ") {
        let dl = get_downloads_dir();
        open_system_command("explorer.exe", &[dl.to_str().unwrap_or("C:\\Downloads")]);
        return VoiceExecutionResult::ok("open_folder", "✓ Downloads folder opened");
    }

    if (lower.contains("desktop") && (lower.contains("kholo") || lower.contains("folder") || lower.contains("open")))
        || raw.contains("ڈیسک ٹاپ")
    {
        let dt = get_desktop_dir();
        open_system_command("explorer.exe", &[dt.to_str().unwrap_or("C:\\Desktop")]);
        return VoiceExecutionResult::ok("open_folder", "✓ Desktop folder opened");
    }

    if lower.contains("documents") || lower.contains("document folder") || raw.contains("ڈاکومنٹس") {
        let docs = get_documents_dir();
        open_system_command("explorer.exe", &[docs.to_str().unwrap_or("C:\\Documents")]);
        return VoiceExecutionResult::ok("open_folder", "✓ Documents folder opened");
    }

    if lower.contains("videos") || lower.contains("video folder") || raw.contains("ویڈیوز") {
        let path = std::env::var("USERPROFILE").map(|p| format!("{}\\Videos", p)).unwrap_or_else(|_| "C:\\Videos".to_string());
        open_system_command("explorer.exe", &[&path]);
        return VoiceExecutionResult::ok("open_folder", "✓ Videos folder opened");
    }

    if lower.contains("pictures") || lower.contains("photos folder") || raw.contains("تصاویر") {
        let path = std::env::var("USERPROFILE").map(|p| format!("{}\\Pictures", p)).unwrap_or_else(|_| "C:\\Pictures".to_string());
        open_system_command("explorer.exe", &[&path]);
        return VoiceExecutionResult::ok("open_folder", "✓ Pictures folder opened");
    }

    // -------------------------------------------------------------
    // 7. YOUTUBE SEARCH & PLAY
    // -------------------------------------------------------------
    if lower.contains("youtube") && (lower.contains("chalao") || lower.contains("play") || lower.contains("search") || lower.contains("dekho") || raw.contains("چلاؤ")) {
        let mut clean_query = lower
            .replace("youtube par chalao", "")
            .replace("youtube par search karo", "")
            .replace("youtube par dekho", "")
            .replace("play on youtube", "")
            .replace("on youtube", "")
            .replace("search on youtube", "")
            .replace("search youtube for", "")
            .replace("youtube par", "")
            .replace("chalao", "")
            .replace("play", "")
            .replace("یوٹیوب پر چلاؤ", "")
            .replace("یوٹیوب پر", "")
            .replace("چلاؤ", "")
            .trim()
            .to_string();

        if clean_query.is_empty() {
            clean_query = "trending".to_string();
        }

        let url = format!("https://www.youtube.com/results?search_query={}", url_encode(&clean_query));
        open_url_or_app(&url);
        return VoiceExecutionResult::ok(
            "youtube_search",
            format!("✓ Playing on YouTube: \"{}\"", clean_query),
        );
    }

    // -------------------------------------------------------------
    // 8. GOOGLE SEARCH
    // -------------------------------------------------------------
    if lower.contains("google par search") || lower.contains("search on google") || lower.contains("search karo") || lower.starts_with("search ") || raw.contains("گوگل پر سرچ") || raw.contains("سرچ کرو") {
        let clean_query = lower
            .replace("google par search karo", "")
            .replace("google par search kar do", "")
            .replace("google par search", "")
            .replace("search on google", "")
            .replace("search for", "")
            .replace("search karo", "")
            .replace("search", "")
            .replace("google par", "")
            .replace("google", "")
            .replace("گوگل پر سرچ کرو", "")
            .replace("گوگل پر", "")
            .replace("سرچ کرو", "")
            .trim()
            .to_string();

        if !clean_query.is_empty() {
            let url = format!("https://www.google.com/search?q={}", url_encode(&clean_query));
            open_url_or_app(&url);
            return VoiceExecutionResult::ok(
                "google_search",
                format!("✓ Searching Google for: \"{}\"", clean_query),
            );
        }
    }

    // -------------------------------------------------------------
    // 9. DIRECT WEBSITES / URLS
    // -------------------------------------------------------------
    if lower.contains(".com") || lower.contains(".org") || lower.contains(".net") || lower.contains(".io") || lower.contains(".pk") || lower.contains(".edu") || lower.starts_with("http://") || lower.starts_with("https://") {
        let mut clean_url = lower
            .replace("open website", "")
            .replace("open", "")
            .replace("kholo", "")
            .replace("khol do", "")
            .replace("کھولو", "")
            .trim()
            .to_string();

        if !clean_url.starts_with("http://") && !clean_url.starts_with("https://") {
            clean_url = format!("https://{}", clean_url);
        }

        open_url_or_app(&clean_url);
        return VoiceExecutionResult::ok("open_website", format!("✓ Opened website: {}", clean_url));
    }

    // -------------------------------------------------------------
    // 10. COMMON DESKTOP APPLICATIONS
    // -------------------------------------------------------------
    if lower.contains("notepad") || raw.contains("نوٹ پیڈ") || raw.contains("نوٹپیڈ") {
        open_system_command("notepad.exe", &[]);
        return VoiceExecutionResult::ok("open_app", "✓ Notepad opened successfully");
    }

    if lower.contains("chrome") || lower.contains("browser") || raw.contains("کروم") {
        open_system_command("cmd", &["/c", "start", "chrome"]);
        return VoiceExecutionResult::ok("open_app", "✓ Google Chrome opened successfully");
    }

    if lower.contains("edge") {
        open_system_command("cmd", &["/c", "start", "msedge"]);
        return VoiceExecutionResult::ok("open_app", "✓ Microsoft Edge opened successfully");
    }

    if lower.contains("word") || lower.contains("winword") || raw.contains("ورڈ") {
        open_system_command("cmd", &["/c", "start", "winword"]);
        return VoiceExecutionResult::ok("open_app", "✓ Microsoft Word opened successfully");
    }

    if lower.contains("excel") || raw.contains("ایکسل") {
        open_system_command("cmd", &["/c", "start", "excel"]);
        return VoiceExecutionResult::ok("open_app", "✓ Microsoft Excel opened successfully");
    }

    if lower.contains("powerpoint") || lower.contains("ppt") || raw.contains("پاور پوائنٹ") {
        open_system_command("cmd", &["/c", "start", "powerpnt"]);
        return VoiceExecutionResult::ok("open_app", "✓ Microsoft PowerPoint opened successfully");
    }

    if lower.contains("calculator") || lower.contains("calc") || raw.contains("کیلکولیٹر") || raw.contains("کلکولیٹر") {
        open_system_command("calc.exe", &[]);
        return VoiceExecutionResult::ok("open_app", "✓ Calculator opened successfully");
    }

    if lower.contains("paint") || raw.contains("پینٹ") {
        open_system_command("mspaint.exe", &[]);
        return VoiceExecutionResult::ok("open_app", "✓ Paint opened successfully");
    }

    if lower.contains("task manager") || raw.contains("ٹاسک مینیجر") {
        open_system_command("taskmgr.exe", &[]);
        return VoiceExecutionResult::ok("open_app", "✓ Task Manager opened");
    }

    if lower.contains("settings") || lower.contains("setting") || raw.contains("سیٹنگز") {
        open_system_command("cmd", &["/c", "start", "ms-settings:"]);
        return VoiceExecutionResult::ok("open_app", "✓ Windows Settings opened");
    }

    if lower.contains("control panel") || raw.contains("کنٹرول پینل") {
        open_system_command("control.exe", &[]);
        return VoiceExecutionResult::ok("open_app", "✓ Control Panel opened");
    }

    if lower.contains("camera") || raw.contains("کیمرہ") {
        open_system_command("cmd", &["/c", "start", "microsoft.windows.camera:"]);
        return VoiceExecutionResult::ok("open_app", "✓ Camera opened");
    }

    if lower.contains("cmd") || lower.contains("command prompt") || lower.contains("terminal") {
        open_system_command("cmd", &["/c", "start", "cmd.exe"]);
        return VoiceExecutionResult::ok("open_app", "✓ Command Prompt opened");
    }

    if lower.contains("powershell") {
        open_system_command("cmd", &["/c", "start", "powershell.exe"]);
        return VoiceExecutionResult::ok("open_app", "✓ PowerShell opened");
    }

    if lower.contains("whatsapp") {
        open_system_command("cmd", &["/c", "start", "whatsapp:"]);
        return VoiceExecutionResult::ok("open_app", "✓ WhatsApp opened");
    }

    if lower.contains("capcut") {
        open_system_command("cmd", &["/c", "start", "CapCut"]);
        return VoiceExecutionResult::ok("open_app", "✓ CapCut opened");
    }

    if lower.contains("zoom") {
        open_system_command("cmd", &["/c", "start", "zoom"]);
        return VoiceExecutionResult::ok("open_app", "✓ Zoom opened");
    }

    if lower.contains("vlc") {
        open_system_command("cmd", &["/c", "start", "vlc"]);
        return VoiceExecutionResult::ok("open_app", "✓ VLC Media Player opened");
    }

    // -------------------------------------------------------------
    // 11. WINDOW & WORKSTATION CONTROLS
    // -------------------------------------------------------------
    if lower.contains("close window") || lower.contains("window band karo") || lower.contains("ye band karo") || lower == "close" || lower == "band karo" || raw.contains("بند کرو") {
        input.send_shortcut("close_window");
        return VoiceExecutionResult::ok("system_control", "✓ Active window closed");
    }

    if lower.contains("minimize") || lower.contains("chota karo") || raw.contains("منیمائز") {
        input.send_shortcut("minimize");
        return VoiceExecutionResult::ok("system_control", "✓ Window minimized");
    }

    if lower.contains("maximize") || lower.contains("bada karo") || lower.contains("full screen") || raw.contains("میکسیمائز") {
        input.send_shortcut("maximize");
        return VoiceExecutionResult::ok("system_control", "✓ Window maximized");
    }

    if lower.contains("switch window") || lower.contains("window badlo") || lower.contains("next window") || raw.contains("ونڈو بدلو") {
        input.send_shortcut("switch_window");
        return VoiceExecutionResult::ok("system_control", "✓ Switched window");
    }

    if lower.contains("show desktop") || lower.contains("desktop dikhao") || raw.contains("ڈیسک ٹاپ دکھاؤ") {
        input.send_shortcut("show_desktop");
        return VoiceExecutionResult::ok("system_control", "✓ Desktop toggled");
    }

    if lower.contains("screenshot") || lower.contains("screen shot") || raw.contains("اسکرین شاٹ") {
        input.send_shortcut("screenshot");
        return VoiceExecutionResult::ok("system_control", "✓ Screenshot taken");
    }

    if lower.contains("lock") && (lower.contains("pc") || lower.contains("computer") || lower.contains("karo")) {
        input.send_shortcut("lock");
        return VoiceExecutionResult::ok("system_control", "✓ Workstation locked");
    }

    // -------------------------------------------------------------
    // 12. AUDIO & MEDIA CONTROLS
    // -------------------------------------------------------------
    if lower.contains("volume up") || lower.contains("awaz barhao") || lower.contains("awaz teez") || raw.contains("آواز بڑھاؤ") {
        input.send_shortcut("volume_up");
        return VoiceExecutionResult::ok("system_control", "✓ Volume increased");
    }

    if lower.contains("volume down") || lower.contains("awaz kam") || raw.contains("آواز کم کرو") {
        input.send_shortcut("volume_down");
        return VoiceExecutionResult::ok("system_control", "✓ Volume decreased");
    }

    if lower.contains("mute") || lower.contains("unmute") || lower.contains("awaz band") || raw.contains("آواز بند") {
        input.send_shortcut("mute");
        return VoiceExecutionResult::ok("system_control", "✓ Volume mute/unmute toggled");
    }

    if lower.contains("play") && lower.contains("pause") || lower == "pause" || lower == "play" || lower == "resume" {
        input.send_shortcut("media_play_pause");
        return VoiceExecutionResult::ok("system_control", "✓ Media Play/Pause toggled");
    }

    if lower.contains("next song") || lower.contains("next track") || lower.contains("agla gana") {
        input.send_shortcut("media_next");
        return VoiceExecutionResult::ok("system_control", "✓ Next track played");
    }

    if lower.contains("previous song") || lower.contains("previous track") || lower.contains("pichla gana") {
        input.send_shortcut("media_prev");
        return VoiceExecutionResult::ok("system_control", "✓ Previous track played");
    }

    // -------------------------------------------------------------
    // 13. GENERAL APP LAUNCH FALLBACK ("open [X]" or "[X] kholo")
    // -------------------------------------------------------------
    if lower.starts_with("open ") || lower.ends_with(" kholo") || lower.ends_with(" khol do") || raw.ends_with(" کھولو") {
        let app_name = lower
            .replace("open", "")
            .replace("kholo", "")
            .replace("khol do", "")
            .replace("کھولو", "")
            .trim()
            .to_string();

        if !app_name.is_empty() {
            let res = open_system_command("cmd", &["/c", "start", "", &app_name]);
            if res {
                return VoiceExecutionResult::ok(
                    "open_app",
                    format!("✓ Opening \"{}\"", app_name),
                );
            }
        }
    }

    // -------------------------------------------------------------
    // 14. POWER CONTROLS (Safety Check)
    // -------------------------------------------------------------
    if (lower.contains("shutdown") || lower.contains("shut down") || lower.contains("pc band karo")) && (lower.contains("pc") || lower.contains("computer")) {
        open_system_command("shutdown", &["/s", "/t", "60"]);
        return VoiceExecutionResult::ok("system_control", "✓ Computer scheduled to shut down in 60 seconds (cancel via 'shutdown -a')");
    }

    if (lower.contains("restart") || lower.contains("reboot")) && (lower.contains("pc") || lower.contains("computer")) {
        open_system_command("shutdown", &["/r", "/t", "60"]);
        return VoiceExecutionResult::ok("system_control", "✓ Computer scheduled to restart in 60 seconds (cancel via 'shutdown -a')");
    }

    // -------------------------------------------------------------
    // 15. GROQ AI VOICE OPERATOR (User API Key Integration)
    // -------------------------------------------------------------
    if let Some(groq_res) = query_groq_ai(raw, input) {
        return groq_res;
    }

    // -------------------------------------------------------------
    // 16. FALLBACK: GOOGLE SEARCH
    // -------------------------------------------------------------
    let fallback_url = format!("https://www.google.com/search?q={}", url_encode(raw));
    open_url_or_app(&fallback_url);
    VoiceExecutionResult::ok(
        "google_search",
        format!("✓ Searching Google for: \"{}\"", raw),
    )
}

fn query_groq_ai(raw: &str, input: &InputEngine) -> Option<VoiceExecutionResult> {
    let api_key = std::env::var("GROQ_API_KEY").unwrap_or_default();
    let system_prompt = "You are KeyLink AI PC Controller. Interpret user commands in Urdu, Roman Urdu, or English and output a JSON object: {\"actions\": [{\"action\": \"open_app\"|\"open_url\"|\"type_text\"|\"press_key\"|\"shortcut\"|\"system\", \"target\": \"string\", \"reply\": \"Roman Urdu confirmation\"}]}. Actions: open_app (chrome, notepad, calc, explorer, zoom), open_url (https://...), type_text (text), press_key (enter, backspace, tab, esc, f5), shortcut (desktop, lock, volume_up, volume_down, mute, copy, paste, select_all, switch_window, media_play_pause), system (lock, task_manager).";

    let payload = serde_json::json!({
        "model": "qwen/qwen3.8-27b",
        "messages": [
            { "role": "system", "content": system_prompt },
            { "role": "user", "content": raw }
        ],
        "response_format": { "type": "json_object" },
        "temperature": 0.1,
        "max_tokens": 150
    });

    let payload_str = payload.to_string();
    let output = Command::new("curl.exe")
        .args(&[
            "-s",
            "-m", "8",
            "-X", "POST",
            "https://api.groq.com/openai/v1/chat/completions",
            "-H", &format!("Authorization: Bearer {}", api_key),
            "-H", "Content-Type: application/json",
            "-H", "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) MobileKemo/1.0",
            "-d", &payload_str,
        ])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let res_text = String::from_utf8_lossy(&output.stdout);
    let v: serde_json::Value = serde_json::from_str(&res_text).ok()?;
    let content = v["choices"][0]["message"]["content"].as_str()?;

    let parsed_val: serde_json::Value = serde_json::from_str(content).ok()?;
    let actions: Vec<serde_json::Value> = if let Some(arr) = parsed_val.get("actions").and_then(|a| a.as_array()) {
        arr.clone()
    } else if let Some(arr) = parsed_val.as_array() {
        arr.clone()
    } else {
        vec![parsed_val]
    };

    let mut replies = Vec::new();
    let mut last_action = String::from("groq_ai");

    for act in actions {
        let action_type = act["action"].as_str().unwrap_or("");
        let target = act["target"].as_str().unwrap_or("");
        let reply = act["reply"].as_str().unwrap_or("");
        if !reply.is_empty() {
            replies.push(reply.to_string());
        }
        last_action = action_type.to_string();

        match action_type {
            "open_app" => {
                let target_lower = target.to_lowercase();
                if target_lower.contains("this pc") || target_lower.contains("computer") || target_lower == "explorer" {
                    let _ = Command::new("cmd").args(&["/c", "start", "", "explorer.exe", "shell:MyComputerFolder"]).spawn();
                } else {
                    let _ = Command::new("cmd").args(&["/c", "start", "", target]).spawn();
                }
            }
            "open_url" => {
                let mut url = target.to_string();
                if !url.starts_with("http://") && !url.starts_with("https://") {
                    url = format!("https://{}", url);
                }
                let _ = Command::new("cmd").args(&["/c", "start", "", &url]).spawn();
            }
            "type_text" => {
                input.send_text(target);
            }
            "press_key" => {
                input.send_key(target, "press", &[]);
            }
            "shortcut" => {
                input.send_shortcut(target);
            }
            "system" => {
                if target == "lock" {
                    input.send_shortcut("lock");
                } else if target == "task_manager" || target == "taskmgr" {
                    let _ = Command::new("cmd").args(&["/c", "start", "taskmgr"]).spawn();
                } else {
                    input.send_shortcut(target);
                }
            }
            _ => {}
        }
    }

    if !replies.is_empty() {
        Some(VoiceExecutionResult::ok(&last_action, format!("✓ {}", replies.join(" | "))))
    } else {
        None
    }
}

fn open_url_or_app(target: &str) {
    #[cfg(target_os = "windows")]
    {
        let _ = Command::new("cmd")
            .args(&["/c", "start", "", target])
            .spawn();
    }
    #[cfg(target_os = "macos")]
    {
        let _ = Command::new("open").arg(target).spawn();
    }
}

fn open_system_command(cmd: &str, args: &[&str]) -> bool {
    #[cfg(target_os = "windows")]
    {
        Command::new(cmd).args(args).spawn().is_ok()
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (cmd, args);
        false
    }
}
