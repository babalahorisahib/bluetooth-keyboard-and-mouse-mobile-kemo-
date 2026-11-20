import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  static const String _keyThemeMode = 'keylink_theme_mode';
  static const String _keySensitivity = 'keylink_sensitivity';
  static const String _keyInvertScroll = 'keylink_invert_scroll';
  static const String _keyHaptics = 'keylink_haptics';
  static const String _keyTapToClick = 'keylink_tap_to_click';

  ThemeMode _themeMode = ThemeMode.dark;
  double _sensitivity = 1.4;
  bool _invertScroll = false;
  bool _hapticsEnabled = true;
  bool _tapToClick = true;

  ThemeMode get themeMode => _themeMode;
  double get sensitivity => _sensitivity;
  bool get invertScroll => _invertScroll;
  bool get hapticsEnabled => _hapticsEnabled;
  bool get tapToClick => _tapToClick;

  SettingsService() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final themeStr = prefs.getString(_keyThemeMode);
    if (themeStr == 'light') {
      _themeMode = ThemeMode.light;
    } else if (themeStr == 'dark') {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.dark; // Default to sleek dark mode
    }

    _sensitivity = (prefs.getDouble(_keySensitivity) ?? 1.4).clamp(0.2, 8.0);
    _invertScroll = prefs.getBool(_keyInvertScroll) ?? false;
    _hapticsEnabled = prefs.getBool(_keyHaptics) ?? true;
    _tapToClick = prefs.getBool(_keyTapToClick) ?? true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, mode == ThemeMode.light ? 'light' : 'dark');
  }

  Future<void> setSensitivity(double value) async {
    _sensitivity = value.clamp(0.2, 8.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySensitivity, _sensitivity);
  }

  Future<void> setInvertScroll(bool value) async {
    _invertScroll = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyInvertScroll, value);
  }

  Future<void> setHapticsEnabled(bool value) async {
    _hapticsEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHaptics, value);
  }

  Future<void> setTapToClick(bool value) async {
    _tapToClick = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyTapToClick, value);
  }
}
