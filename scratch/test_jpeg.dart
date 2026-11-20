import 'dart:io';
import 'dart:typed_data';

void main() {
  final b = File('scratch/captured_frame.jpg').readAsBytesSync();
  print('read ${b.length} bytes');
  int i = 2;
  while (i + 4 < b.length) {
    if (b[i] != 0xFF) { i++; continue; }
    final m = b[i + 1];
    if (m == 0xC0 || m == 0xC1 || m == 0xC2) {
      final h = (b[i + 5] << 8) | b[i + 6];
      final w = (b[i + 7] << 8) | b[i + 8];
      print('JPEG dimensions: $w x $h');
      break;
    }
    if (m == 0xD9 || m == 0xDA) break;
    if (m == 0x01 || (m >= 0xD0 && m <= 0xD7)) { i += 2; continue; }
    if (i + 3 >= b.length) break;
    final len = (b[i + 2] << 8) | b[i + 3];
    i += 2 + len;
  }
}
