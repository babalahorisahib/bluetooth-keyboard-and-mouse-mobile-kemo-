import React, { useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { Copy, Check, QrCode } from 'lucide-react';
import { ServerState } from '../types';

interface Props {
  state: ServerState;
}

export const QrCodeCard: React.FC<Props> = ({ state }) => {
  const [copied, setCopied] = useState(false);

  const handleCopyIp = () => {
    navigator.clipboard.writeText(`${state.localIp}:${state.port}`);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="card">
      <div className="card-title">
        <QrCode size={18} color="#3b82f6" />
        <span>Connect Your Phone</span>
      </div>
      <div className="qr-box">
        <div className="qr-frame">
          <QRCodeSVG
            value={state.qrPayload || JSON.stringify({ ip: state.localIp, port: state.port, pin: state.pin, name: state.serverName })}
            size={180}
            level="H"
            includeMargin={true}
          />
        </div>
        <div className="pin-display">
          <span className="pin-label">Pairing PIN</span>
          <span className="pin-value">{state.pin}</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '13px' }}>
          <span style={{ color: 'var(--text-secondary)' }}>Host:</span>
          <strong>{state.localIp}:{state.port}</strong>
          <button
            onClick={handleCopyIp}
            className="icon-btn"
            style={{ width: '28px', height: '28px', borderRadius: '6px' }}
            title="Copy Host IP"
          >
            {copied ? <Check size={14} color="#10b981" /> : <Copy size={14} />}
          </button>
        </div>
        <p style={{ fontSize: '12px', color: 'var(--text-secondary)', textAlign: 'center', maxWidth: '300px' }}>
          Open Mobile Kemo on your phone and scan this QR code to connect instantly.
        </p>
      </div>
    </div>
  );
};
