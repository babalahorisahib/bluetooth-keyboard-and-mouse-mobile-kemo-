import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:keylink_mobile/main.dart';
import 'package:keylink_mobile/services/connection_service.dart';
import 'package:keylink_mobile/services/settings_service.dart';
import 'package:keylink_mobile/screens/touchscreen_screen.dart';
import 'package:keylink_mobile/touchpad/touchpad_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('KeyLinkApp launches and displays title', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final settingsService = SettingsService();
    final connectionService = ConnectionService();

    await tester.pumpWidget(KeyLinkApp(
      settingsService: settingsService,
      connectionService: connectionService,
    ));

    expect(find.text('Mobile Kemo'), findsWidgets);
    expect(find.text('Remote Controller'), findsOneWidget);
    expect(find.text('Scan Desktop QR Code'), findsOneWidget);

    // Clean up services
    connectionService.dispose();
    settingsService.dispose();
  });

  testWidgets('TouchscreenScreen and TouchpadScreen instantiate cleanly', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final settingsService = SettingsService();
    final connectionService = ConnectionService();

    // Allow async init to finish
    await tester.pump(const Duration(milliseconds: 100));

    // Verify TouchscreenScreen can be created
    final touchscreen = TouchscreenScreen(
      connectionService: connectionService,
      settingsService: settingsService,
    );
    expect(touchscreen, isNotNull);

    // Verify TouchpadScreen can be created
    final touchpad = TouchpadScreen(
      connectionService: connectionService,
      settingsService: settingsService,
    );
    expect(touchpad, isNotNull);

    connectionService.dispose();
    settingsService.dispose();
  });
}
