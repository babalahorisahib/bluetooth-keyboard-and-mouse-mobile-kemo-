import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

void main() async {
  print('====================================================');
  print('     KEMO SERVER RESTART & TUNNEL RECOVERY TEST      ');
  print('====================================================\n');

  final hashInput = 'kemo_rendezvous:waseem:179887';
  final hashHex = sha256.convert(utf8.encode(hashInput)).toString();
  final secureTopic = 'kemo_v2_${hashHex.substring(0, 20)}';

  print('Querying secure presence topic: $secureTopic');
  final httpClient = HttpClient()..connectionTimeout = const Duration(seconds: 4);
  final req = await httpClient.getUrl(Uri.parse('https://ntfy.sh/$secureTopic/json?poll=1'));
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  httpClient.close();

  String latestTunnel = '';
  int latestTs = 0;

  for (final line in body.split('\n').reversed) {
    if (line.trim().isEmpty) continue;
    try {
      final parsed = jsonDecode(line);
      final msgStr = parsed['message'] as String?;
      if (msgStr != null) {
        final msgObj = jsonDecode(msgStr);
        final t = msgObj['tunnel'] as String?;
        final ts = msgObj['ts'] as int? ?? 0;
        if (t != null && t.isNotEmpty && ts > latestTs) {
          latestTunnel = t;
          latestTs = ts;
        }
      }
    } catch (_) {}
  }

  print('Discovered live tunnel from rendezvous: $latestTunnel (timestamp: $latestTs)');

  if (latestTunnel.isEmpty) {
    print('[FAIL] No tunnel discovered from rendezvous topic.');
    exit(1);
  }

  // Connect over WSS to the newly discovered tunnel
  try {
    final customClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..badCertificateCallback = ((cert, host, port) => true);
    final ws = await WebSocket.connect('wss://$latestTunnel', customClient: customClient).timeout(const Duration(seconds: 8));

    final completer = Completer<bool>();
    ws.listen((data) {
      if (data is String && data.contains('APPROVED')) {
        completer.complete(true);
      }
    });

    ws.add(jsonEncode({
      'type': 'PAIR_REQUEST',
      'id': 'recovery-test-1',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'payload': {
        'device_id': 'recovery-tester-phone',
        'device_name': 'Recovery Test Device',
        'os': 'android',
        'pin': '179887'
      }
    }));

    final ok = await completer.future.timeout(const Duration(seconds: 5), onTimeout: () => false);
    await ws.close();

    if (ok) {
      print('[PASS] Successfully connected to restarted server via dynamic rendezvous tunnel: wss://$latestTunnel');
      exit(0);
    } else {
      print('[FAIL] Pairing was not approved on wss://$latestTunnel');
      exit(1);
    }
  } catch (e) {
    print('[FAIL] Could not connect to wss://$latestTunnel: $e');
    exit(1);
  }
}
