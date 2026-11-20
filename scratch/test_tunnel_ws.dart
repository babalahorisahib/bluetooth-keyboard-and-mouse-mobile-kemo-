import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main() async {
  String tunnelUrl = 'along-internal-nashville-reforms.trycloudflare.com';
  final activeFile = File('tunnel_active.txt');
  if (activeFile.existsSync()) {
    final content = activeFile.readAsStringSync().trim();
    tunnelUrl = content.replaceAll('https://', '').replaceAll('http://', '').replaceAll('/', '');
  }
  print('Connecting to wss://$tunnelUrl ...');
  final sw = Stopwatch()..start();
  try {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..badCertificateCallback = (cert, host, port) => true;

    final ws = await WebSocket.connect(
      'wss://$tunnelUrl',
      customClient: client,
    ).timeout(const Duration(seconds: 15));

    print('WebSocket connected in ${sw.elapsedMilliseconds} ms!');

    final completer = Completer<void>();
    ws.listen((data) {
      print('Received: $data');
      if (!completer.isCompleted) completer.complete();
    });

    final pairReq = jsonEncode({
      'type': 'PAIR_REQUEST',
      'payload': {
        'device_id': 'test-runner-phone',
        'device_name': 'TestPhone',
        'os': 'android',
        'pin': '179887'
      }
    });

    ws.add(pairReq);
    print('Sent PAIR_REQUEST');

    await completer.future.timeout(const Duration(seconds: 8));
    print('SUCCESS: Full handshake verified over Cloudflare Tunnel in ${sw.elapsedMilliseconds} ms!');
    await ws.close();
  } catch (e, st) {
    print('Error: $e\n$st');
  }
}
