#[cfg(target_os = "windows")]
pub mod windows;
#[cfg(target_os = "windows")]
pub mod screen_capture;
#[cfg(target_os = "windows")]
pub mod audio_capture;
#[cfg(target_os = "windows")]
pub mod audio_playback;
#[cfg(target_os = "windows")]
pub use windows::WindowsDriver as ActiveDriver;

#[cfg(target_os = "macos")]
pub mod macos;
#[cfg(target_os = "macos")]
pub use macos::MacOsDriver as ActiveDriver;

// Fallback stub for unsupported platforms or test builds
#[cfg(not(any(target_os = "windows", target_os = "macos")))]
pub mod stub {
    pub struct StubDriver;
    impl StubDriver {
        pub fn new() -> Self { StubDriver }
        pub fn mouse_move(&self, _dx: f64, _dy: f64) {}
        pub fn mouse_click(&self, _button: &str, _action: &str) {}
        pub fn mouse_scroll(&self, _dx: f64, _dy: f64) {}
        pub fn send_text(&self, _text: &str) {}
        pub fn send_key(&self, _key: &str, _action: &str, _modifiers: &[String]) {}
        pub fn send_shortcut(&self, _action: &str) {}
    }
}
#[cfg(not(any(target_os = "windows", target_os = "macos")))]
pub use stub::StubDriver as ActiveDriver;

pub struct InputEngine {
    driver: ActiveDriver,
    #[cfg(target_os = "windows")]
    capturer: screen_capture::ScreenCapture,
}

impl InputEngine {
    pub fn new() -> Self {
        InputEngine {
            driver: ActiveDriver::new(),
            #[cfg(target_os = "windows")]
            capturer: screen_capture::ScreenCapture::new(),
        }
    }

    pub fn mouse_move(&self, dx: f64, dy: f64) {
        self.driver.mouse_move(dx, dy);
    }

    pub fn mouse_click(&self, button: &str, action: &str) {
        self.driver.mouse_click(button, action);
    }

    pub fn mouse_scroll(&self, dx: f64, dy: f64) {
        self.driver.mouse_scroll(dx, dy);
    }

    pub fn send_text(&self, text: &str) {
        self.driver.send_text(text);
    }

    pub fn send_key(&self, key: &str, action: &str, modifiers: &[String]) {
        self.driver.send_key(key, action, modifiers);
    }

    pub fn send_shortcut(&self, action: &str) {
        self.driver.send_shortcut(action);
    }

    pub fn touch_event(&self, action: &str, x: f64, y: f64) {
        #[cfg(target_os = "windows")]
        self.driver.touch_event(action, x, y);
    }

    pub fn capture_screen(&self, max_width: u32, quality: u8) -> Option<Vec<u8>> {
        #[cfg(target_os = "windows")]
        {
            self.capturer.capture_frame(max_width, quality)
        }
        #[cfg(not(target_os = "windows"))]
        {
            None
        }
    }

    pub fn reset_screen_cache(&self) {
        #[cfg(target_os = "windows")]
        {
            self.capturer.reset_cache();
        }
    }
}
