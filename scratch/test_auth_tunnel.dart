import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main() async {
  final content = File('tunnel_active.txt').readAsStringSync().trim();
  final tunnelUrl = content.replaceAll('https://', '').replaceAll('http://', '').replaceAll('/', '');
  final client = HttpClient()..badCertificateCallback = (c, h, p) => true;
  final ws = await WebSocket.connect('wss://$tunnelUrl', customClient: client).timeout(const Duration(seconds: 15));
  print('Connected to wss://$tunnelUrl');
  final completer = Completer<void>();
  ws.listen((data) {
    print('Received: $data');
    if (!completer.isCompleted) completer.complete();
  });
  final authReq = jsonEncode({
    'type': 'AUTH_REQUEST',
    'payload': {
      'device_id': 'test-runner-phone',
      'device_name': 'TestPhone',
      'auth_token': '19692afa-43ec-4190-80e5-06b0444aca19',
      'os': 'android'
    }
  });
  ws.add(authReq);
  await completer.future.timeout(const Duration(seconds: 8));
  print('SUCCESS: AUTH_REQUEST approved over Cloudflare Tunnel!');
  await ws.close();
}
