export interface ConnectedClient {
  id: string;
  name: string;
  ip: string;
  os: string;
  connectedAt: string;
  lastPingMs: number;
}

export interface ServerState {
  running: boolean;
  serverName: string;
  localIp: string;
  port: number;
  pin: string;
  qrPayload: string;
  connectedClients: ConnectedClient[];
  os: 'windows' | 'macos';
  accessibilityPermission: boolean;
}

export interface BluetoothDevice {
  name: string;
  address: string;
  paired: boolean;
  connected: boolean;
}

export interface AppSettings {
  autoStart: boolean;
  minimizeToTray: boolean;
  sensitivity: number;
  invertScroll: boolean;
  theme: 'dark' | 'light';
}
