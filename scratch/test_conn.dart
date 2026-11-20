import 'dart:io';

void main() async {
  try {
    print('Testing 127.0.0.1:58921...');
    final s1 = await Socket.connect('127.0.0.1', 58921, timeout: Duration(seconds: 2));
    print('127.0.0.1 connected!');
    s1.destroy();
  } catch (e) {
    print('127.0.0.1 failed: $e');
  }

  try {
    print('Testing 192.168.1.109:58921...');
    final s2 = await Socket.connect('192.168.1.109', 58921, timeout: Duration(seconds: 2));
    print('192.168.1.109 connected!');
    s2.destroy();
  } catch (e) {
    print('192.168.1.109 failed: $e');
  }
}
