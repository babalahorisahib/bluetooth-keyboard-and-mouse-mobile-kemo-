use std::collections::HashMap;
use std::sync::Mutex;
use std::fs;
use uuid::Uuid;
use rand::Rng;
use serde::{Deserialize, Serialize};

const AUTH_FILE_PATH: &str = "C:\\bluetooth keyboard and mouse\\auth_store.json";

#[derive(Serialize, Deserialize, Default)]
struct AuthStore {
    pin: String,
    tokens: HashMap<String, String>, // device_id -> token
}

pub struct AuthManager {
    pin: Mutex<String>,
    tokens: Mutex<HashMap<String, String>>, // device_id -> token
}

impl AuthManager {
    pub fn new() -> Self {
        let mut loaded_pin = String::new();
        let mut loaded_tokens = HashMap::new();

        if let Ok(content) = fs::read_to_string(AUTH_FILE_PATH) {
            if let Ok(store) = serde_json::from_str::<AuthStore>(&content) {
                if !store.pin.is_empty() {
                    loaded_pin = store.pin;
                }
                loaded_tokens = store.tokens;
            }
        }

        if loaded_pin.is_empty() {
            loaded_pin = format!("{:06}", rand::thread_rng().gen_range(100000..999999));
        }

        let manager = AuthManager {
            pin: Mutex::new(loaded_pin),
            tokens: Mutex::new(loaded_tokens),
        };
        manager.save_to_disk();
        manager
    }

    fn save_to_disk(&self) {
        let store = AuthStore {
            pin: self.get_pin(),
            tokens: self.tokens.lock().unwrap().clone(),
        };
        if let Ok(json) = serde_json::to_string_pretty(&store) {
            let _ = fs::write(AUTH_FILE_PATH, json);
        }
    }

    pub fn get_pin(&self) -> String {
        self.pin.lock().unwrap().clone()
    }

    pub fn set_pin(&self, new_pin: String) {
        {
            let mut p = self.pin.lock().unwrap();
            *p = new_pin;
        }
        self.save_to_disk();
    }

    /// Verify pairing PIN and generate a secure session token for authorized device.
    pub fn verify_pair_request(&self, device_id: &str, entered_pin: &str) -> Option<String> {
        if device_id.is_empty() || entered_pin.trim().is_empty() {
            return None;
        }
        let current_pin = self.get_pin();
        if entered_pin.trim() != current_pin.trim() {
            eprintln!("[AUTH] Rejected pair request: invalid PIN from device '{}'", device_id);
            return None;
        }
        let mut tokens = self.tokens.lock().unwrap();
        let token = Uuid::new_v4().to_string();
        tokens.insert(device_id.to_string(), token.clone());
        drop(tokens);
        self.save_to_disk();
        println!("[AUTH] Approved pairing for device '{}'. Generated secure auth token.", device_id);
        Some(token)
    }

    /// Verify that the device presents a valid, previously authorized token
    pub fn verify_auth_token(&self, device_id: &str, token: &str) -> bool {
        if device_id.is_empty() || token.is_empty() {
            return false;
        }
        let tokens = self.tokens.lock().unwrap();
        if let Some(stored) = tokens.get(device_id) {
            if stored == token {
                return true;
            }
        }
        eprintln!("[AUTH] Rejected auth attempt: invalid token for device '{}'", device_id);
        false
    }

    pub fn revoke_device(&self, device_id: &str) {
        let mut tokens = self.tokens.lock().unwrap();
        tokens.remove(device_id);
        drop(tokens);
        self.save_to_disk();
    }
}
