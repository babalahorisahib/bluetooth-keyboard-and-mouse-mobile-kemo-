import 'dart:io';

void main() {
  final path = 'mobile/lib/screens/home_screen.dart';
  final lines = File(path).readAsLinesSync();
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].contains('Text(') && i + 1 < lines.length && lines[i + 1].contains('device.name,')) {
      lines.insert(i + 2, '                                        maxLines: 1,');
      lines.insert(i + 3, '                                        overflow: TextOverflow.ellipsis,');
      print('Inserted at line $i');
      break;
    }
  }
  File(path).writeAsStringSync(lines.join('\n'));
}
