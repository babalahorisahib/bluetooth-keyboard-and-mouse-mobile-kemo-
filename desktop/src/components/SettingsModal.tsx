import React from 'react';
import { X, Sliders, ShieldCheck, AlertCircle } from 'lucide-react';
import { AppSettings, ServerState } from '../types';

interface Props {
  isOpen: boolean;
  onClose: () => void;
  settings: AppSettings;
  serverState: ServerState;
  onUpdateSettings: (settings: Partial<AppSettings>) => void;
  onRequestAccessibility?: () => void;
}

export const SettingsModal: React.FC<Props> = ({
  isOpen,
  onClose,
  settings,
  serverState,
  onUpdateSettings,
  onRequestAccessibility,
}) => {
  if (!isOpen) return null;

  return (
    <div
      style={{
        position: 'fixed',
        top: 0,
        left: 0,
        right: 0,
        bottom: 0,
        backgroundColor: 'rgba(0, 0, 0, 0.65)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        zIndex: 1000,
      }}
    >
      <div
        className="card"
        style={{
          width: '460px',
          maxWidth: '90%',
          maxHeight: '90vh',
          overflowY: 'auto',
          position: 'relative',
        }}
      >
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <Sliders size={20} color="#3b82f6" />
            <h3 style={{ fontSize: 18, fontWeight: 700 }}>Mobile Kemo Preferences</h3>
          </div>
          <button className="icon-btn" onClick={onClose} style={{ width: 32, height: 32 }}>
            <X size={16} />
          </button>
        </div>

        {/* macOS Accessibility Notice if on macOS */}
        {serverState.os === 'macos' && (
          <div
            style={{
              padding: 14,
              borderRadius: 12,
              marginBottom: 16,
              background: serverState.accessibilityPermission
                ? 'rgba(16, 185, 129, 0.12)'
                : 'rgba(245, 158, 11, 0.12)',
              border: `1px solid ${
                serverState.accessibilityPermission
                  ? 'rgba(16, 185, 129, 0.4)'
                  : 'rgba(245, 158, 11, 0.4)'
              }`,
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
              {serverState.accessibilityPermission ? (
                <>
                  <ShieldCheck size={18} color="#10b981" />
                  <strong style={{ color: '#10b981', fontSize: 13 }}>Accessibility Granted</strong>
                </>
              ) : (
                <>
                  <AlertCircle size={18} color="#f59e0b" />
                  <strong style={{ color: '#f59e0b', fontSize: 13 }}>Accessibility Required</strong>
                </>
              )}
            </div>
            <p style={{ fontSize: 12, color: 'var(--text-secondary)' }}>
              macOS requires Accessibility permissions to synthesize mouse and keyboard events.
            </p>
            {!serverState.accessibilityPermission && onRequestAccessibility && (
              <button
                className="btn-primary"
                style={{ marginTop: 10, fontSize: 12, padding: '6px 12px' }}
                onClick={onRequestAccessibility}
              >
                Open System Settings
              </button>
            )}
          </div>
        )}

        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <div>
            <label style={{ fontSize: 13, fontWeight: 600, display: 'block', marginBottom: 6 }}>
              Pointer Sensitivity ({settings.sensitivity.toFixed(1)}x)
            </label>
            <input
              type="range"
              min="0.5"
              max="3.0"
              step="0.1"
              value={settings.sensitivity}
              onChange={(e) => onUpdateSettings({ sensitivity: parseFloat(e.target.value) })}
              style={{ width: '100%' }}
            />
          </div>

          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <div style={{ fontSize: 14, fontWeight: 600 }}>Natural Scrolling</div>
              <div style={{ fontSize: 12, color: 'var(--text-secondary)' }}>Invert scroll wheel direction</div>
            </div>
            <input
              type="checkbox"
              checked={settings.invertScroll}
              onChange={(e) => onUpdateSettings({ invertScroll: e.target.checked })}
              style={{ width: 18, height: 18, cursor: 'pointer' }}
            />
          </div>

          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <div style={{ fontSize: 14, fontWeight: 600 }}>Minimize to System Tray</div>
              <div style={{ fontSize: 12, color: 'var(--text-secondary)' }}>Keep running in background when closed</div>
            </div>
            <input
              type="checkbox"
              checked={settings.minimizeToTray}
              onChange={(e) => onUpdateSettings({ minimizeToTray: e.target.checked })}
              style={{ width: 18, height: 18, cursor: 'pointer' }}
            />
          </div>

          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <div style={{ fontSize: 14, fontWeight: 600 }}>Dark Theme</div>
              <div style={{ fontSize: 12, color: 'var(--text-secondary)' }}>Toggle dark / light appearance</div>
            </div>
            <input
              type="checkbox"
              checked={settings.theme === 'dark'}
              onChange={(e) => onUpdateSettings({ theme: e.target.checked ? 'dark' : 'light' })}
              style={{ width: 18, height: 18, cursor: 'pointer' }}
            />
          </div>
        </div>

        <div style={{ marginTop: 24, display: 'flex', justifyContent: 'flex-end' }}>
          <button className="btn-primary" onClick={onClose}>
            Done
          </button>
        </div>
      </div>
    </div>
  );
};
