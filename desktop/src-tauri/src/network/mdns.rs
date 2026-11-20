use mdns_sd::{ServiceDaemon, ServiceInfo};
use std::collections::HashMap;

pub struct MdnsBroadcaster {
    daemon: Option<ServiceDaemon>,
}

impl MdnsBroadcaster {
    pub fn new() -> Self {
        MdnsBroadcaster { daemon: None }
    }

    pub fn start(&mut self, server_name: &str, port: u16, ip: &str) {
        if let Ok(mdns) = ServiceDaemon::new() {
            let service_type = "_keylink._tcp.local.";
            let instance_name = server_name;
            let host_name = format!("{}.local.", server_name.replace(' ', "-").to_lowercase());
            let properties: HashMap<String, String> = HashMap::new();

            if let Ok(service_info) = ServiceInfo::new(
                service_type,
                instance_name,
                &host_name,
                ip,
                port,
                properties,
            ) {
                let _ = mdns.register(service_info);
                self.daemon = Some(mdns);
            }
        }
    }

    pub fn stop(&mut self) {
        if let Some(daemon) = self.daemon.take() {
            let _ = daemon.shutdown();
        }
    }
}
