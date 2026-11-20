import 'dart:io';

void main() {
  for (final path in [
    'mobile/lib/screens/home_screen.dart',
    'mobile/lib/screens/touchscreen_screen.dart',
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      final text = file.readAsStringSync().replaceAll('\r\n', '\n');
      file.writeAsStringSync(text);
      print('Fixed to LF: $path');
    }
  }
}
