import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

void main() async {
  final hash = sha256.convert(utf8.encode('kemo_rendezvous:waseem:179887')).toString();
  final topic = 'kemo_v2_${hash.substring(0, 20)}';
  print('Topic: $topic');
  final res = await Process.run('curl.exe', ['-s', 'https://ntfy.sh/$topic/json?poll=1']);
  print('Output:\n${res.stdout}');
}
