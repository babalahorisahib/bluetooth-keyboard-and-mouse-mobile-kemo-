import React from 'react';
import { Smartphone, Wifi, Power } from 'lucide-react';
import { ConnectedClient } from '../types';

interface Props {
  clients: ConnectedClient[];
  onDisconnectClient: (id: string) => void;
}

export const ConnectedDevices: React.FC<Props> = ({ clients = [], onDisconnectClient }) => {
  const safeClients = Array.isArray(clients) ? clients : [];
  return (
    <div className="card">
      <div className="card-title">
        <Smartphone size={18} color="#10b981" />
        <span>Connected Devices ({safeClients.length})</span>
      </div>
      <div className="device-list">
        {safeClients.length === 0 ? (
          <div className="empty-state">
            <Wifi size={32} style={{ opacity: 0.3, marginBottom: 8 }} />
            <p>No phone connected yet.</p>
            <p style={{ fontSize: '11px', marginTop: 4 }}>
              Scan the QR code to pair your device.
            </p>
          </div>
        ) : (
          safeClients.map((client) => (
            <div key={client.id} className="device-item">
              <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                <div
                  style={{
                    width: 38,
                    height: 38,
                    borderRadius: 10,
                    background: 'rgba(59, 130, 246, 0.15)',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    color: '#3b82f6',
                  }}
                >
                  <Smartphone size={20} />
                </div>
                <div className="device-details">
                  <h4>{client.name}</h4>
                  <p>
                    {client.ip} • Latency: {client.lastPingMs}ms
                  </p>
                </div>
              </div>
              <button
                className="btn-danger"
                onClick={() => onDisconnectClient(client.id)}
                title="Disconnect Phone"
              >
                <Power size={13} style={{ marginRight: 4, verticalAlign: 'middle' }} />
                Disconnect
              </button>
            </div>
          ))
        )}
      </div>
    </div>
  );
};
