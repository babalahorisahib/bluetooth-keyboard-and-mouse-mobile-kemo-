import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';
import 'services/connection_service.dart';
import 'services/settings_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  final settingsService = SettingsService();
  final connectionService = ConnectionService();

  runApp(KeyLinkApp(
    settingsService: settingsService,
    connectionService: connectionService,
  ));
}

class KeyLinkApp extends StatefulWidget {
  final SettingsService settingsService;
  final ConnectionService connectionService;

  const KeyLinkApp({
    super.key,
    required this.settingsService,
    required this.connectionService,
  });

  @override
  State<KeyLinkApp> createState() => _KeyLinkAppState();
}

class _KeyLinkAppState extends State<KeyLinkApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.connectionService.onAppResumed();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      widget.connectionService.onAppBackgrounded();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.settingsService,
      builder: (context, _) {
        return MaterialApp(
          title: 'Mobile Kemo',
          debugShowCheckedModeBanner: false,
          themeMode: widget.settingsService.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2563EB),
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
            appBarTheme: const AppBarTheme(
              elevation: 0,
              backgroundColor: Colors.transparent,
              centerTitle: false,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF3B82F6),
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: const Color(0xFF0D0F14),
            cardColor: const Color(0xFF161A22),
            appBarTheme: const AppBarTheme(
              elevation: 0,
              backgroundColor: Colors.transparent,
              centerTitle: false,
            ),
          ),
          home: HomeScreen(
            connectionService: widget.connectionService,
            settingsService: widget.settingsService,
          ),
        );
      },
    );
  }
}
