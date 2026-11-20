import 'dart:io';

void main() {
  final res = Process.runSync('git', ['show', '333ee6d:mobile/lib/screens/touchscreen_screen.dart']);
  final str = res.stdout as String;
  final idx = str.indexOf('Widget _buildTrackpadArea()');
  if (idx != -1) {
    print(str.substring(idx, idx + 1000));
  }
}
