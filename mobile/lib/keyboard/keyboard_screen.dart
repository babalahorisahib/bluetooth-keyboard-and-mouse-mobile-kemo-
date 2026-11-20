import 'package:flutter/material.dart';
import '../services/connection_service.dart';
import '../services/settings_service.dart';
import '../touchpad/touchpad_screen.dart';

class KeyboardScreen extends StatelessWidget {
  final ConnectionService connectionService;
  final SettingsService settingsService;

  const KeyboardScreen({
    super.key,
    required this.connectionService,
    required this.settingsService,
  });

  @override
  Widget build(BuildContext context) {
    return TouchpadScreen(
      connectionService: connectionService,
      settingsService: settingsService,
      autoFocusKeyboard: true,
    );
  }
}
