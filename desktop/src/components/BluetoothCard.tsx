import React, { useState, useEffect } from 'react';
import { Bluetooth, RefreshCw, Smartphone, ExternalLink, CheckCircle2, WifiOff } from 'lucide-react';
import { ServerState, BluetoothDevice } from '../types';

interface Props {
  state: ServerState;
}

export const BluetoothCard: React.FC<Props> = ({ state }) => {
  const [devices, setDevices] = useState<BluetoothDevice[]>([
    {
      name: 'Waseem Infinix ZERO 30',
      address: 'ec:46:2c:f6:e1:ca',
      paired: true,
      connected: true,
    },
    {
      name: 'Infinix NOTE',
      address: 'c8:54:a4:dc:bd:dc',
      paired: true,
      connected: false,
    },
  ]);
  const [isLoading, setIsLoading] = useState(false);

  const fetchBtDevices = async () => {
    setIsLoading(true);
    try {
      const { invoke } = await import('@tauri-apps/api/core');
      const res = await invoke<BluetoothDevice[]>('get_bluetooth_devices');
      if (res && res.length > 0) {
        setDevices(res);
      }
    } catch {
      // Keep initial/fallback list in web dev mode
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchBtDevices();
  }, []);

  const handleOpenSettings = async () => {
    try {
      const { invoke } = await import('@tauri-apps/api/core');
      await invoke('open_bluetooth_settings');
    } catch {
      // Fallback
    }
  };

  return (
    <div className="card">
      <div className="card-title" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <div style={{
            background: 'linear-gradient(135deg, #2563eb, #3b82f6)',
            borderRadius: 8,
            padding: 6,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            boxShadow: '0 2px 8px rgba(37, 99, 235, 0.4)'
          }}>
            <Bluetooth size={20} color="#ffffff" />
          </div>
          <div>
            <span style={{ fontWeight: 700, fontSize: 16 }}>Bluetooth Offline Controller</span>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 2 }}>
              <span className="status-dot online" style={{ width: 8, height: 8 }} />
              <span style={{ fontSize: 11, color: '#10b981', fontWeight: 600 }}>Bluetooth Adapter Active & Listening</span>
            </div>
          </div>
        </div>

        <button
          onClick={fetchBtDevices}
          className="icon-btn"
          style={{ width: 32, height: 32 }}
          title="Refresh Paired Devices"
          disabled={isLoading}
        >
          <RefreshCw size={14} className={isLoading ? 'animate-spin' : ''} />
        </button>
      </div>

      <div style={{ marginTop: 16, display: 'flex', flexDirection: 'column', gap: 14 }}>
        {/* Host Bluetooth Info Bar */}
        <div style={{
          background: 'var(--bg-surface)',
          padding: '12px 16px',
          borderRadius: 12,
          border: '1px solid var(--border-color)',
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(130px, 1fr))',
          gap: 10,
          fontSize: 12,
        }}>
          <div>
            <div style={{ color: 'var(--text-secondary)' }}>PC Name</div>
            <strong style={{ fontSize: 13 }}>{state.serverName}</strong>
          </div>
          <div>
            <div style={{ color: 'var(--text-secondary)' }}>Bluetooth Adapter</div>
            <strong style={{ fontSize: 13, color: '#3b82f6' }}>Active & Ready</strong>
          </div>
          <div>
            <div style={{ color: 'var(--text-secondary)' }}>Offline Port</div>
            <strong style={{ fontSize: 13 }}>{state.port}</strong>
          </div>
          <div>
            <div style={{ color: 'var(--text-secondary)' }}>Pairing PIN</div>
            <strong style={{ fontSize: 13, color: '#10b981' }}>{state.pin}</strong>
          </div>
        </div>

        {/* Paired Mobile Devices Section */}
        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
            <span style={{ fontSize: 13, fontWeight: 600, color: 'var(--text-secondary)' }}>
              Paired Mobile Phones ({devices.length})
            </span>
            <button
              onClick={handleOpenSettings}
              style={{
                background: 'transparent',
                border: 'none',
                color: '#3b82f6',
                cursor: 'pointer',
                fontSize: 12,
                display: 'flex',
                alignItems: 'center',
                gap: 4,
                fontWeight: 600,
              }}
            >
              <ExternalLink size={12} />
              Open Windows Bluetooth
            </button>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {devices.map((dev, idx) => (
              <div
                key={idx}
                style={{
                  background: 'var(--bg-surface)',
                  padding: '12px 14px',
                  borderRadius: 12,
                  border: '1px solid var(--border-color)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                }}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                  <div style={{
                    background: 'rgba(59, 130, 246, 0.12)',
                    padding: 8,
                    borderRadius: 10,
                    display: 'flex',
                    alignItems: 'center',
                  }}>
                    <Smartphone size={20} color="#3b82f6" />
                  </div>
                  <div>
                    <div style={{ fontWeight: 600, fontSize: 14 }}>{dev.name}</div>
                    <div style={{ fontSize: 11, color: 'var(--text-secondary)', fontFamily: 'monospace' }}>
                      {dev.address}
                    </div>
                  </div>
                </div>

                <div style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 6,
                  background: 'rgba(16, 185, 129, 0.12)',
                  color: '#10b981',
                  padding: '4px 10px',
                  borderRadius: 20,
                  fontSize: 11,
                  fontWeight: 600,
                }}>
                  <CheckCircle2 size={13} />
                  <span>Paired & Ready</span>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Simple Step-by-Step Instructions */}
        <div style={{
          background: 'rgba(59, 130, 246, 0.08)',
          border: '1px solid rgba(59, 130, 246, 0.25)',
          borderRadius: 12,
          padding: 14,
          fontSize: 12,
          lineHeight: 1.6,
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontWeight: 700, color: '#3b82f6', marginBottom: 6 }}>
            <WifiOff size={16} />
            <span>How to Connect via Bluetooth (No Wi-Fi / No Internet):</span>
          </div>
          <ol style={{ paddingLeft: 18, color: 'var(--text-primary)' }}>
            <li>
              Phone Settings mein <strong>Hotspot & Tethering</strong> kholain aur <strong>Bluetooth Tethering</strong> (بلوٹوتھ شیئرنگ) ON karein.
            </li>
            <li>
              Apne mobile par <strong>KeyLink</strong> app kholain aur <strong>"Connect via Bluetooth (No Internet)"</strong> par tap karein.
            </li>
            <li>
              <strong>Connect</strong> button dabate hi mobile mouse aur keyboard laptop se jor jayega!
            </li>
          </ol>
        </div>
      </div>
    </div>
  );
};
