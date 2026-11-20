use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Serialize, Deserialize)]
pub struct WireMessage {
    pub v: Option<u32>,
    pub r#type: String,
    pub id: Option<String>,
    #[serde(default)]
    pub payload: Value,
}

#[derive(Debug)]
pub enum InputCommand {
    MouseMove { dx: f64, dy: f64 },
    MouseClick { button: String, action: String },
    MouseScroll { dx: f64, dy: f64 },
    TextInput { text: String },
    KeyEvent { key: String, action: String, modifiers: Vec<String> },
    Shortcut { action: String },
    Ping { timestamp: i64 },
    VoiceCommand { text: String, lang: Option<String> },
    ScreenStreamStart { quality: u8, max_width: u32, fps: u32 },
    ScreenStreamStop,
    AudioStreamStart,
    AudioStreamStop,
    MicStreamStart,
    MicStreamStop,
    TouchEvent { action: String, x: f64, y: f64 },
    Disconnect { reason: String },
    Other,
}

impl WireMessage {
    pub fn to_command(&self) -> InputCommand {
        match self.r#type.as_str() {
            "MOUSE_MOVE" => {
                let dx = self.payload.get("dx").and_then(|v| v.as_f64()).unwrap_or(0.0);
                let dy = self.payload.get("dy").and_then(|v| v.as_f64()).unwrap_or(0.0);
                InputCommand::MouseMove { dx, dy }
            }
            "MOUSE_CLICK" => {
                let button = self.payload.get("button").and_then(|v| v.as_str()).unwrap_or("left").to_string();
                let action = self.payload.get("action").and_then(|v| v.as_str()).unwrap_or("click").to_string();
                InputCommand::MouseClick { button, action }
            }
            "MOUSE_SCROLL" => {
                let dx = self.payload.get("dx").and_then(|v| v.as_f64()).unwrap_or(0.0);
                let dy = self.payload.get("dy").and_then(|v| v.as_f64()).unwrap_or(0.0);
                InputCommand::MouseScroll { dx, dy }
            }
            "TEXT_INPUT" => {
                let text = self.payload.get("text").and_then(|v| v.as_str()).unwrap_or("").to_string();
                InputCommand::TextInput { text }
            }
            "KEY_EVENT" => {
                let key = self.payload.get("key").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let action = self.payload.get("action").and_then(|v| v.as_str()).unwrap_or("press").to_string();
                let modifiers = self.payload.get("modifiers")
                    .and_then(|v| v.as_array())
                    .map(|arr| arr.iter().filter_map(|m| m.as_str().map(|s| s.to_string())).collect())
                    .unwrap_or_default();
                InputCommand::KeyEvent { key, action, modifiers }
            }
            "SHORTCUT" => {
                let action = self.payload.get("action").and_then(|v| v.as_str()).unwrap_or("").to_string();
                InputCommand::Shortcut { action }
            }
            "PING" => {
                let timestamp = self.payload.get("timestamp").and_then(|v| v.as_i64()).unwrap_or(0);
                InputCommand::Ping { timestamp }
            }
            "VOICE_COMMAND" => {
                let text = self.payload.get("text").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let lang = self.payload.get("lang").and_then(|v| v.as_str()).map(|s| s.to_string());
                InputCommand::VoiceCommand { text, lang }
            }
            "SCREEN_STREAM_START" | "START_SCREEN_STREAM" => {
                let quality = self.payload.get("quality").and_then(|v| v.as_u64()).unwrap_or(65) as u8;
                let max_width = self.payload.get("max_width").and_then(|v| v.as_u64()).unwrap_or(1280) as u32;
                let fps = self.payload.get("fps").and_then(|v| v.as_u64()).unwrap_or(20) as u32;
                InputCommand::ScreenStreamStart { quality, max_width, fps }
            }
            "SCREEN_STREAM_STOP" | "STOP_SCREEN_STREAM" => {
                InputCommand::ScreenStreamStop
            }
            "AUDIO_STREAM_START" | "START_AUDIO_STREAM" => {
                InputCommand::AudioStreamStart
            }
            "AUDIO_STREAM_STOP" | "STOP_AUDIO_STREAM" => {
                InputCommand::AudioStreamStop
            }
            "MIC_STREAM_START" | "START_MIC_STREAM" => {
                InputCommand::MicStreamStart
            }
            "MIC_STREAM_STOP" | "STOP_MIC_STREAM" => {
                InputCommand::MicStreamStop
            }
            "TOUCH_EVENT" => {
                let action = self.payload.get("action").and_then(|v| v.as_str()).unwrap_or("tap").to_string();
                let x = self.payload.get("x").and_then(|v| v.as_f64()).unwrap_or(0.0);
                let y = self.payload.get("y").and_then(|v| v.as_f64()).unwrap_or(0.0);
                InputCommand::TouchEvent { action, x, y }
            }
            "DISCONNECT" => {
                let reason = self.payload.get("reason").and_then(|v| v.as_str()).unwrap_or("client_disconnect").to_string();
                InputCommand::Disconnect { reason }
            }
            _ => InputCommand::Other,
        }
    }
}
