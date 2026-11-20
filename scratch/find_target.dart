import 'dart:convert';
import 'dart:io';

void main() {
  final res = Process.runSync('cargo', ['metadata', '--no-deps', '--format-version', '1'], workingDirectory: r'C:\bluetooth keyboard and mouse\desktop\src-tauri');
  final map = jsonDecode(res.stdout as String) as Map<String, dynamic>;
  print('target_directory: ${map['target_directory']}');
}
