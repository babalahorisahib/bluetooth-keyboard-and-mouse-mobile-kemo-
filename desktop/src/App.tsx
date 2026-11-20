import React, { useState, useEffect } from 'react';
import { Settings, Shield, RefreshCw, Moon, Sun } from 'lucide-react';
import logoImg from './assets/logo.png';
import { ServerState, AppSettings, ConnectedClient } from './types';
import { QrCodeCard } from './components/QrCodeCard';
import { ConnectedDevices } from './components/ConnectedDevices';
import { SettingsModal } from './components/SettingsModal';

export const App: React.FC = () => {
  const [serverState, setServerState] = useState<ServerState>({
    running: true,
    serverName: 'KeyLink Host',
    localIp: '192.168.1.109',
    port: 58921,
    pin: Math.floor(100000 + Math.random() * 900000).toString(),
    qrPayload: '',
    connectedClients: [],
    os: 'windows',
    accessibilityPermission: true,
  });

  const [settings, setSettings] = useState<AppSettings>({
    autoStart: false,
    minimizeToTray: true,
    sensitivity: 1.2,
    invertScroll: false,
    theme: 'dark',
  });

  const [isSettingsOpen, setIsSettingsOpen] = useState(false);

  const normalizeState = (raw: any): ServerState => {
    if (!raw) return serverState;
    const rawClients = raw.connectedClients || raw.connected_clients || [];
    const clients: ConnectedClient[] = Array.isArray(rawClients)
      ? rawClients.map((c: any) => ({
          id: c.id || '',
          name: c.name || 'Unknown Device',
          ip: c.ip || '',
          os: c.os || 'unknown',
          connectedAt: c.connectedAt ?? c.connected_at ?? '',
          lastPingMs: c.lastPingMs ?? c.last_ping_ms ?? 0,
        }))
      : [];

    return {
      running: raw.running ?? true,
      serverName: raw.serverName ?? raw.server_name ?? 'KeyLink Host',
      localIp: raw.localIp ?? raw.local_ip ?? '127.0.0.1',
      port: raw.port ?? 58921,
      pin: raw.pin ?? '123456',
      qrPayload: raw.qrPayload ?? raw.qr_payload ?? '',
      connectedClients: clients,
      os: raw.os === 'macos' ? 'macos' : 'windows',
      accessibilityPermission: raw.accessibilityPermission ?? raw.accessibility_permission ?? true,
    };
  };

  // Sync theme to document body
  useEffect(() => {
    document.documentElement.setAttribute('data-theme', settings.theme);
  }, [settings.theme]);

  // Connect to Tauri backend if running in Tauri
  useEffect(() => {
    let unlisten: (() => void) | undefined;

    async function initTauri() {
      try {
        const { invoke } = await import('@tauri-apps/api/core');
        const state = await invoke<any>('get_server_state');
        if (state) {
          setServerState(normalizeState(state));
        }

        const { listen } = await import('@tauri-apps/api/event');
        unlisten = await listen<any>('server-state-update', (event) => {
          if (event?.payload) {
            setServerState(normalizeState(event.payload));
          }
        });
      } catch {
        // Running in browser dev mode or Tauri not initialized yet
      }
    }

    initTauri();

    return () => {
      if (unlisten) unlisten();
    };
  }, []);

  const handleDisconnectClient = async (id: string) => {
    try {
      const { invoke } = await import('@tauri-apps/api/core');
      await invoke('disconnect_client', { clientId: id, client_id: id });
    } catch {
      // Dev mode fallback
    }
    setServerState((prev) => ({
      ...prev,
      connectedClients: prev.connectedClients.filter((c) => c.id !== id),
    }));
  };

  const handleRegeneratePin = async () => {
    const newPin = Math.floor(100000 + Math.random() * 900000).toString();
    try {
      const { invoke } = await import('@tauri-apps/api/core');
      const updated = await invoke<any>('set_pin', { pin: newPin });
      if (updated) {
        setServerState(normalizeState(updated));
      } else {
        setServerState((prev) => ({ ...prev, pin: newPin }));
      }
    } catch {
      setServerState((prev) => ({ ...prev, pin: newPin }));
    }
  };

  const handleUpdateSettings = (newSettings: Partial<AppSettings>) => {
    setSettings((prev) => ({ ...prev, ...newSettings }));
  };

  const toggleTheme = () => {
    handleUpdateSettings({ theme: settings.theme === 'dark' ? 'light' : 'dark' });
  };

  return (
    <div className="app-container">
      {/* Header */}
      <header className="header">
        <div className="logo-group">
          <div className="logo-icon" style={{ background: 'transparent', padding: 0 }}>
            <img src={logoImg} alt="Mobile Kemo" style={{ width: 36, height: 36, borderRadius: 8, objectFit: 'cover' }} />
          </div>
          <div className="logo-text">
            <h1>Mobile Kemo</h1>
            <p>Your Phone. Your Computer Controller.</p>
          </div>
        </div>
        <div className="header-actions">
          <button className="icon-btn" onClick={toggleTheme} title="Toggle Theme">
            {settings.theme === 'dark' ? <Sun size={18} /> : <Moon size={18} />}
          </button>
          <button className="icon-btn" onClick={() => setIsSettingsOpen(true)} title="Preferences">
            <Settings size={18} />
          </button>
        </div>
      </header>

      {/* Status Banner */}
      <div className="status-banner">
        <div className="status-left">
          <div className={`status-indicator ${serverState.running ? 'online' : 'offline'}`} />
          <div className="server-info">
            <h3>{serverState.running ? 'Mobile Kemo Server Active' : 'Server Stopped'}</h3>
            <p>
              Local Wi-Fi Network • Port {serverState.port} • IP: {serverState.localIp}
            </p>
          </div>
        </div>
        <button
          className="icon-btn"
          onClick={handleRegeneratePin}
          title="Regenerate Pairing PIN"
        >
          <RefreshCw size={16} />
        </button>
      </div>

      {/* Main Grid */}
      <main className="main-grid">
        <QrCodeCard state={serverState} />
        <ConnectedDevices
          clients={serverState.connectedClients}
          onDisconnectClient={handleDisconnectClient}
        />
      </main>

      {/* Footer */}
      <footer className="footer">
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6 }}>
          <Shield size={14} color="#3b82f6" />
          <span>Mobile Kemo • Ultra-Low Latency Wi-Fi Connection • Zero Cloud Dependency</span>
        </div>
      </footer>

      {/* Settings Modal */}
      <SettingsModal
        isOpen={isSettingsOpen}
        onClose={() => setIsSettingsOpen(false)}
        settings={settings}
        serverState={serverState}
        onUpdateSettings={handleUpdateSettings}
      />
    </div>
  );
};
