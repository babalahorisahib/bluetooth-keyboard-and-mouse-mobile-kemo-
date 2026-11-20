import 'package:flutter/material.dart';
import '../services/connection_service.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatelessWidget {
  final ConnectionService connectionService;
  final SettingsService settingsService;

  const SettingsScreen({
    super.key,
    required this.connectionService,
    required this.settingsService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([settingsService, connectionService]),
          builder: (context, _) {
            final isConnected = connectionService.isConnected;

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              children: [
                // Emergency Disconnect Button
                if (isConnected) ...[
                  Card(
                    color: Colors.red.withValues(alpha: 0.12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.security, color: Colors.red, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Emergency Control',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade400,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Immediately cuts off all connection and remote input to the connected computer.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              icon: const Icon(Icons.power_settings_new),
                              label: const Text('Emergency Disconnect Now'),
                              onPressed: () => connectionService.emergencyDisconnect(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Appearance Section
                _sectionHeader('Appearance'),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                          color: Colors.blueAccent,
                        ),
                        title: const Text('Dark Mode'),
                        subtitle: Text(isDark ? 'Dark theme active' : 'Light theme active'),
                        trailing: Switch(
                          value: isDark,
                          onChanged: (val) {
                            settingsService.setThemeMode(val ? ThemeMode.dark : ThemeMode.light);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Touchpad & Mouse Section
                _sectionHeader('Touchpad & Controls'),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.speed_outlined, color: Colors.blueAccent),
                          title: const Text('Pointer Sensitivity'),
                          subtitle: Text('${settingsService.sensitivity.toStringAsFixed(1)}x'),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Slider(
                            value: settingsService.sensitivity.clamp(0.4, 8.0),
                            min: 0.4,
                            max: 8.0,
                            divisions: 76,
                            label: '${settingsService.sensitivity.toStringAsFixed(1)}x',
                            onChanged: (val) => settingsService.setSensitivity(val),
                          ),
                        ),
                        const Divider(indent: 16, endIndent: 16),
                        SwitchListTile(
                          secondary: const Icon(Icons.swipe_vertical_outlined, color: Colors.blueAccent),
                          title: const Text('Natural Scrolling'),
                          subtitle: const Text('Invert scroll wheel direction'),
                          value: settingsService.invertScroll,
                          onChanged: (val) => settingsService.setInvertScroll(val),
                        ),
                        const Divider(indent: 16, endIndent: 16),
                        SwitchListTile(
                          secondary: const Icon(Icons.touch_app_outlined, color: Colors.blueAccent),
                          title: const Text('Tap to Click'),
                          subtitle: const Text('Single tap for left click, two fingers for right click'),
                          value: settingsService.tapToClick,
                          onChanged: (val) => settingsService.setTapToClick(val),
                        ),
                        const Divider(indent: 16, endIndent: 16),
                        SwitchListTile(
                          secondary: Icon(
                            connectionService.isAudioStreaming
                                ? Icons.volume_up_rounded
                                : Icons.volume_off_rounded,
                            color: connectionService.isAudioStreaming
                                ? const Color(0xFF10B981)
                                : Colors.blueAccent,
                          ),
                          title: const Text('Real-Time PC Audio Streaming'),
                          subtitle: Text(connectionService.isAudioStreaming
                              ? 'Active (Streaming PC sound to phone)'
                              : 'Disabled (Muted)'),
                          value: connectionService.isAudioStreaming,
                          onChanged: connectionService.isConnected
                              ? (val) {
                                  connectionService.toggleAudioStream();
                                }
                              : null,
                        ),
                        const Divider(indent: 16, endIndent: 16),
                        SwitchListTile(
                          secondary: const Icon(Icons.vibration_outlined, color: Colors.blueAccent),
                          title: const Text('Haptic Feedback'),
                          subtitle: const Text('Vibrate phone on tap, click, or shortcut'),
                          value: settingsService.hapticsEnabled,
                          onChanged: (val) => settingsService.setHapticsEnabled(val),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Paired Computers Management
                _sectionHeader('Paired Computers'),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: connectionService.pairedDevices.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(20.0),
                          child: Center(
                            child: Text(
                              'No paired devices saved yet.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: connectionService.pairedDevices.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final device = connectionService.pairedDevices[i];
                            return ListTile(
                              leading: const Icon(Icons.computer_rounded, color: Colors.blueAccent),
                              title: Text(device.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('${device.ip}:${device.port} • ${device.os}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                tooltip: 'Forget Computer',
                                onPressed: () => connectionService.forgetDevice(device.id),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
