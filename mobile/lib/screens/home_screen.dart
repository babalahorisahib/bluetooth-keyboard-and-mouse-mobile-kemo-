import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../network/transport_interface.dart';
import '../services/connection_service.dart';
import '../services/settings_service.dart';
import '../touchpad/touchpad_screen.dart';
import 'touchscreen_screen.dart';
import 'qr_scanner_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final ConnectionService connectionService;
  final SettingsService settingsService;

  const HomeScreen({
    super.key,
    required this.connectionService,
    required this.settingsService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime? _lastBackPressTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final saved = widget.connectionService.pairedDevices;
      if (saved.isNotEmpty && !widget.connectionService.isConnected) {
        final active = widget.connectionService.activeDevice ?? saved.first;
        if (active.autoConnectEnabled) {
          widget.connectionService.autoConnect(targetDevice: active);
        }
      }
    });
  }

  void _confirmRemoveDevice(BuildContext context, dynamic device) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2330),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Remove ${device.name}?', style: const TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ],
        ),
        content: Text(
          'This will permanently delete authentication credentials on both this phone and the PC.\n\nRe-pairing will require fresh PIN approval from the PC.',
          style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.connectionService.removeDevice(device);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Removed ${device.name} from paired devices.'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            },
            child: const Text('Remove Device'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit Mobile Kemo'),
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Row(
            children: [
              Icon(Icons.smartphone_rounded, color: Colors.blueAccent, size: 26),
              SizedBox(width: 8),
              Text(
                'Mobile Kemo',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(
                      connectionService: widget.connectionService,
                      settingsService: widget.settingsService,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: AnimatedBuilder(
          animation: Listenable.merge([widget.connectionService, widget.settingsService]),
          builder: (context, _) {
            final isConnected = widget.connectionService.isConnected;
            final isConnecting = widget.connectionService.status == ConnectionStatus.connecting ||
                widget.connectionService.status == ConnectionStatus.authenticating;

            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Connection Status Banner Card
                    _buildConnectionBanner(context, isDark, isConnected, isConnecting),

                    const SizedBox(height: 16),

                    // Primary Unified Controller: PC Touch Screen & Mouse
                    _unifiedControllerCard(
                      context,
                      title: 'PC Touch Screen & Mouse',
                      subtitle: 'Direct PC Touch • Live Mirror • Gesture Mouse • Keyboard',
                      icon: Icons.touch_app_rounded,
                      color: Colors.blueAccent,
                      enabled: isConnected,
                      onTap: () {
                        if (!isConnected) {
                          _showNotConnectedSnackBar(context);
                          return;
                        }
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TouchscreenScreen(
                              connectionService: widget.connectionService,
                              settingsService: widget.settingsService,
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 12),

                    // Secondary Card: Classic Trackpad (For relative touch cursor mode)
                    _unifiedControllerCard(
                      context,
                      title: 'Classic Trackpad',
                      subtitle: 'Relative Touchpad Mouse • Hardware Gestures',
                      icon: Icons.mouse_rounded,
                      color: const Color(0xFF10B981),
                      enabled: isConnected,
                      onTap: () {
                        if (!isConnected) {
                          _showNotConnectedSnackBar(context);
                          return;
                        }
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TouchpadScreen(
                              connectionService: widget.connectionService,
                              settingsService: widget.settingsService,
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    // Universal Connectivity info banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF3B82F6), width: 1.2),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.wifi_tethering_rounded, color: Colors.lightBlueAccent, size: 22),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Auto-connects on Local Wi-Fi, 4G Cellular Data, or Remote Internet.',
                              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (isConnected) ...[
                      const SizedBox(height: 10),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          widget.connectionService.toggleAudioStream();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: widget.connectionService.isAudioStreaming
                                ? const Color(0xFF064E3B)
                                : const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: widget.connectionService.isAudioStreaming
                                  ? const Color(0xFF10B981)
                                  : Colors.white24,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                widget.connectionService.isAudioStreaming
                                    ? Icons.volume_up_rounded
                                    : Icons.volume_off_rounded,
                                color: widget.connectionService.isAudioStreaming
                                    ? const Color(0xFF34D399)
                                    : Colors.white60,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  widget.connectionService.isAudioStreaming
                                      ? 'Live PC Audio Streaming Active (Tap to Mute)'
                                      : 'PC Audio Streaming Muted (Tap to Stream)',
                                  style: TextStyle(
                                    color: widget.connectionService.isAudioStreaming
                                        ? const Color(0xFFE6FFFA)
                                        : Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // 1-Tap Universal Auto-Connect Button (Local Wi-Fi + 4G Cloud Relay)
                    SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.flash_on_rounded, size: 22, color: Colors.amberAccent),
                        label: Text(
                          isConnecting ? 'Auto-Connecting to PC...' : '⚡ 1-Tap Fast Connect (No QR Needed)',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        onPressed: isConnecting
                            ? null
                            : () {
                                final saved = widget.connectionService.pairedDevices;
                                if (saved.isNotEmpty) {
                                  widget.connectionService.autoConnect(targetDevice: saved.first);
                                } else {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => QrScannerScreen(
                                        connectionService: widget.connectionService,
                                      ),
                                    ),
                                  );
                                }
                              },
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Pair New PC Button (Wi-Fi QR)
                    SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.qr_code_scanner_rounded, size: 22),
                        label: const Text(
                          'Scan Desktop QR Code',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => QrScannerScreen(
                                connectionService: widget.connectionService,
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Manual IP Connect Button
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        side: BorderSide(
                          color: isDark ? const Color(0xFF2C3446) : const Color(0xFFCBD5E1),
                        ),
                      ),
                      icon: const Icon(Icons.lan_outlined, size: 20),
                      label: const Text('Connect Manually via IP'),
                      onPressed: () => _showManualIpDialog(context),
                    ),

                    const SizedBox(height: 24),

                    // Previously Paired Devices Section
                    Row(
                      children: [
                        Text(
                          'Previously Paired Computers',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${widget.connectionService.pairedDevices.length} saved',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (widget.connectionService.pairedDevices.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF161A22) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? const Color(0xFF232A38) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.desktop_windows_outlined,
                                size: 36,
                                color: isDark ? Colors.white24 : Colors.black26,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'No paired computers yet',
                                style: TextStyle(color: Colors.grey, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ...widget.connectionService.pairedDevices.map((device) {
                        final isThisActive = widget.connectionService.activeDevice?.id == device.id &&
                            isConnected;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1A1F2B) : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isThisActive
                                  ? Colors.green.withValues(alpha: 0.5)
                                  : (isDark ? const Color(0xFF2B3345) : const Color(0xFFE2E8F0)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.computer_rounded,
                                color: isThisActive ? Colors.green : Colors.blueAccent,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      device.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      '${device.ip}:${device.port}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              if (isThisActive) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Active',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () {
                                    widget.connectionService.disconnect(explicitUserDisconnect: true);
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                                    ),
                                    child: const Text(
                                      'Disconnect',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.amber,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ] else
                                TextButton(
                                  onPressed: () {
                                    widget.connectionService.autoConnect(targetDevice: device);
                                  },
                                  child: const Text('Connect'),
                                ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                tooltip: 'Remove Device',
                                onPressed: () => _confirmRemoveDevice(context, device),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildConnectionBanner(
    BuildContext context,
    bool isDark,
    bool isConnected,
    bool isConnecting,
  ) {
    Color cardColor;
    Color borderColor;
    String title;
    String subtitle;
    IconData icon;

    if (isConnected) {
      cardColor = isDark ? const Color(0xFF142B20) : const Color(0xFFECFDF5);
      borderColor = isDark ? const Color(0xFF1E4B35) : const Color(0xFFA7F3D0);
      final active = widget.connectionService.activeDevice;
      final isBt = widget.connectionService.connectionMode == ConnectionMode.bluetooth;
      title = active?.name ?? 'Connected Computer';
      subtitle = isBt
          ? 'Connected via Bluetooth • ${widget.connectionService.connectionQuality}'
          : '${widget.connectionService.connectionMedium} • ${widget.connectionService.connectionQuality}';
      icon = isBt ? Icons.bluetooth_connected_rounded : Icons.check_circle_rounded;
    } else if (isConnecting) {
      cardColor = isDark ? const Color(0xFF2C2412) : const Color(0xFFFFFBEB);
      borderColor = isDark ? const Color(0xFF4C3C1A) : const Color(0xFFFDE68A);
      title = 'Connecting to ${widget.connectionService.activeDevice?.name ?? 'PC'}...';
      subtitle = 'Auto-detecting Local Wi-Fi & 4G Relay';
      icon = Icons.sync_rounded;
    } else {
      cardColor = isDark ? const Color(0xFF161A22) : Colors.white;
      borderColor = isDark ? const Color(0xFF283142) : const Color(0xFFE2E8F0);
      title = 'No Computer Connected';
      subtitle = 'Tap ⚡ 1-Tap Fast Connect or scan QR code';
      icon = Icons.cloud_off_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isConnected
                  ? Colors.green.withValues(alpha: 0.2)
                  : (isConnecting
                      ? Colors.amber.withValues(alpha: 0.2)
                      : Colors.blueAccent.withValues(alpha: 0.1)),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isConnected
                  ? Colors.green
                  : (isConnecting ? Colors.amber : Colors.blueAccent),
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (widget.connectionService.lastError != null && !isConnected) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.connectionService.lastError!,
                    style: const TextStyle(fontSize: 11, color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
          if (isConnected)
            IconButton(
              icon: const Icon(Icons.power_settings_new_rounded, color: Colors.redAccent),
              tooltip: 'Disconnect',
              onPressed: () => widget.connectionService.disconnect(explicitUserDisconnect: true),
            ),
        ],
      ),
    );
  }

  Widget _unifiedControllerCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E2330) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: enabled
                ? Colors.blueAccent.withValues(alpha: isDark ? 0.6 : 0.4)
                : (isDark ? const Color(0xFF2C3446) : const Color(0xFFE2E8F0)),
            width: enabled ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: (enabled ? color : Colors.grey).withValues(alpha: isDark ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                color: enabled ? color : Colors.grey,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      if (enabled) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'ACTIVE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: enabled ? color : Colors.grey.withValues(alpha: 0.4),
              size: 26,
            ),
          ],
        ),
      ),
    );
  }

  void _showNotConnectedSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please connect to your PC via QR code or Bluetooth first.'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showManualIpDialog(BuildContext context) {
    final ipController = TextEditingController(text: '192.168.1.109');
    final pinController = TextEditingController();
    final portController = TextEditingController(text: '58921');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cable_rounded, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('Connect Manually'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ipController,
                decoration: const InputDecoration(
                  labelText: 'Computer IP or 4G Relay URL',
                  hintText: '192.168.1.109 or xxx.trycloudflare.com',
                  prefixIcon: Icon(Icons.language_rounded),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  '💡 At home use Wi-Fi IP (192.168.x.x). Outside use 4G Relay URL shown on PC.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              TextField(
                controller: pinController,
                decoration: const InputDecoration(
                  labelText: 'Security PIN (from PC screen)',
                  hintText: 'e.g. 179887',
                  prefixIcon: Icon(Icons.pin_rounded),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: portController,
                decoration: const InputDecoration(
                  labelText: 'Port (default 58921 / 443)',
                  hintText: '58921',
                  prefixIcon: Icon(Icons.tag_rounded),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              String raw = ipController.text.trim();
              raw = raw.replaceFirst(RegExp(r'^(https?|wss?)://'), '');
              raw = raw.replaceAll(RegExp(r'/+$'), '');

              final pin = pinController.text.trim();
              if (raw.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter Computer IP or 4G Relay URL')),
                );
                return;
              }
              if (pin.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter 6-digit Security PIN shown on PC')),
                );
                return;
              }

              final bool isDomain = raw.contains('.') && RegExp(r'[a-zA-Z]').hasMatch(raw);
              final port = int.tryParse(portController.text.trim()) ?? (isDomain ? 443 : 58921);

              Navigator.of(ctx).pop();
              widget.connectionService.pairWithServer(
                host: raw,
                port: port,
                pin: pin,
                serverName: 'WASEEM',
                tunnel: isDomain ? raw : null,
              );
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}