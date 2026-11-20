import 'dart:io';

void main() {
  final bytes = File('scratch/captured_frame.jpg').readAsBytesSync();
  print('captured_frame.jpg size: ${bytes.length} bytes');
  // Check JFIF header
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
    print('Valid JPEG header');
  }
}
