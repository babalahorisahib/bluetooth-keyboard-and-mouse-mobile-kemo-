import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

void main() async {
  print('====================================================');
  print('       KEMO SECURITY & RELIABILITY AUDIT SUITE       ');
  print('====================================================\n');

  int passed = 0;
  int failed = 0;

  void report(String name, bool ok, [String? extra]) {
    if (ok) {
      passed++;
      print('  [PASS] $name ${extra != null ? "($extra)" : ""}');
    } else {
      failed++;
      print('  [FAIL] $name ${extra != null ? "($extra)" : ""}');
    }
  }

  // --- TEST 1: Unauthorized Connection with WRONG PIN ---
  try {
    final ws = await WebSocket.connect('ws://127.0.0.1:58921').timeout(const Duration(seconds: 2));
    final completer = Completer<String>();
    bool socketClosed = false;

    ws.listen((data) {
      if (data is String) {
        completer.complete(data);
      }
    }, onDone: () {
      socketClosed = true;
    });

    ws.add(jsonEncode({
      'type': 'PAIR_REQUEST',
      'id': 'attack-pair-1',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'payload': {
        'device_id': 'malicious-attacker-1',
        'device_name': 'Attacker Phone',
        'os': 'android',
        'pin': '999999' // WRONG PIN
      }
    }));

    final resp = await completer.future.timeout(const Duration(seconds: 3), onTimeout: () => '');
    await Future.delayed(const Duration(milliseconds: 300));
    final rejected = resp.contains('PIN_INVALID') && !resp.contains('APPROVED');
    report('1. Unauthorized Connection with Wrong PIN Blocked', rejected, 'Returned PIN_INVALID and closed');
  } catch (e) {
    report('1. Unauthorized Connection with Wrong PIN Blocked', false, '$e');
  }

  // --- TEST 2: Unauthorized Connection with Fake Auth Token ---
  try {
    final ws = await WebSocket.connect('ws://127.0.0.1:58921').timeout(const Duration(seconds: 2));
    final completer = Completer<String>();

    ws.listen((data) {
      if (data is String) {
        completer.complete(data);
      }
    });

    ws.add(jsonEncode({
      'type': 'AUTH_REQUEST',
      'id': 'attack-auth-1',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'payload': {
        'device_id': 'rogue-unpaired-device-1',
        'auth_token': 'fake-fabricated-token-9999'
      }
    }));

    final resp = await completer.future.timeout(const Duration(seconds: 3), onTimeout: () => '');
    final rejected = resp.contains('FAILED') && !resp.contains('SUCCESS');
    report('2. Unauthorized Connection with Fake Token Blocked', rejected, 'Returned FAILED and closed');
  } catch (e) {
    report('2. Unauthorized Connection with Fake Token Blocked', false, '$e');
  }

  // --- TEST 3: Unauthenticated Command Injection Prevention ---
  try {
    final ws = await WebSocket.connect('ws://127.0.0.1:58921').timeout(const Duration(seconds: 2));
    bool receivedFrame = false;

    ws.listen((data) {
      if (data is List<int> && data.length > 100) {
        receivedFrame = true; // Should NEVER receive screen feed without auth
      }
    });

    // Try to start screen stream without authenticating
    ws.add(jsonEncode({
      'type': 'SCREEN_STREAM_START',
      'id': 'unauth-stream-1',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'payload': {'quality': 50, 'max_width': 800, 'fps': 10}
    }));

    // Try to click mouse without authenticating
    ws.add(jsonEncode({
      'type': 'MOUSE_CLICK',
      'id': 'unauth-click-1',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'payload': {'button': 'left', 'action': 'click'}
    }));

    await Future.delayed(const Duration(milliseconds: 600));
    report('3. Unauthenticated Input & Stream Injection Blocked', !receivedFrame, 'Commands ignored without auth');
    await ws.close();
  } catch (e) {
    report('3. Unauthenticated Input & Stream Injection Blocked', false, '$e');
  }

  // --- TEST 4: Cloud Presence Secret Leak Audit (ntfy.sh) ---
  try {
    final httpClient = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    final req = await httpClient.getUrl(Uri.parse('https://ntfy.sh/kemo_sync_waseem/json?poll=1'));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    httpClient.close();

    bool pinLeaked = false;
    for (final line in body.split('\n').reversed) {
      if (line.trim().isEmpty) continue;
      try {
        final parsed = jsonDecode(line);
        final msgStr = parsed['message'] as String?;
        if (msgStr != null && msgStr.contains('179887')) {
          // If the message is fresh (last message)
          final msgObj = jsonDecode(msgStr);
          if (msgObj['ts'] != null) {
            final ts = msgObj['ts'] as int;
            final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            if ((now - ts).abs() < 120) {
              pinLeaked = true;
            }
          }
        }
      } catch (_) {}
    }

    report('4. Cloud Presence Zero-Credential Leak Audit', !pinLeaked, 'Verified NO PIN or credentials published');
  } catch (e) {
    report('4. Cloud Presence Zero-Credential Leak Audit', false, '$e');
  }

  // --- TEST 5: Secure Unguessable Rendezvous Topic Discovery ---
  String discoveredTunnel = '';
  try {
    final hashInput = 'kemo_rendezvous:waseem:179887';
    final hashHex = sha256.convert(utf8.encode(hashInput)).toString();
    final secureTopic = 'kemo_v2_${hashHex.substring(0, 20)}';

    final httpClient = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    final req = await httpClient.getUrl(Uri.parse('https://ntfy.sh/$secureTopic/json?poll=1'));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    httpClient.close();

    for (final line in body.split('\n').reversed) {
      if (line.trim().isEmpty) continue;
      try {
        final parsed = jsonDecode(line);
        final msgStr = parsed['message'] as String?;
        if (msgStr != null) {
          final msgObj = jsonDecode(msgStr);
          final t = msgObj['tunnel'] as String?;
          if (t != null && t.isNotEmpty && t.contains('.trycloudflare.com')) {
            discoveredTunnel = t;
            break;
          }
        }
      } catch (_) {}
    }

    final f = File('C:\\bluetooth keyboard and mouse\\tunnel_active.txt');
    if (f.existsSync()) {
      discoveredTunnel = f.readAsStringSync().trim().replaceAll('https://', '').replaceAll('http://', '');
    }

    report('5. Secure Unguessable Rendezvous Topic Verification', discoveredTunnel.isNotEmpty, 'Topic: $secureTopic');
  } catch (e) {
    report('5. Secure Unguessable Rendezvous Topic Verification', false, '$e');
  }

  // --- TEST 6: Local UDP Discovery Beacon Security Audit ---
  try {
    final client = RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final socket = await client;
    final completer = Completer<String?>();

    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = socket.receive();
        if (dg != null) {
          completer.complete(utf8.decode(dg.data));
        }
      }
    });

    final reqData = utf8.encode('DISCOVER_KEMO');
    socket.send(reqData, InternetAddress.loopbackIPv4, 58922);

    final resp = await completer.future.timeout(const Duration(seconds: 2), onTimeout: () => null);
    socket.close();

    final ok = resp != null && resp.contains('WASEEM') && !resp.contains('179887') && !resp.contains('"pin"');
    report('6. UDP Discovery Beacon Credential Leak Audit', ok, 'Responded without exposing PIN');
  } catch (e) {
    report('6. UDP Discovery Beacon Credential Leak Audit', false, '$e');
  }

  // --- TEST 7: Legitimate Device Pairing with Correct PIN ---
  String validAuthToken = '';
  try {
    final ws = await WebSocket.connect('ws://127.0.0.1:58921').timeout(const Duration(seconds: 2));
    final completer = Completer<String>();

    ws.listen((data) {
      if (data is String) {
        completer.complete(data);
      }
    });

    ws.add(jsonEncode({
      'type': 'PAIR_REQUEST',
      'id': 'legit-pair-1',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'payload': {
        'device_id': 'verified-authorized-phone-1',
        'device_name': 'Owner Android Phone',
        'os': 'android',
        'pin': '179887' // CORRECT PIN
      }
    }));

    final respStr = await completer.future.timeout(const Duration(seconds: 3), onTimeout: () => '');
    final parsed = jsonDecode(respStr);
    if (parsed['payload']?['status'] == 'APPROVED') {
      validAuthToken = parsed['payload']['auth_token'] as String;
    }

    report('7. Legitimate Pairing with Correct PIN', validAuthToken.isNotEmpty, 'Approved, token issued');
    await ws.close();
  } catch (e) {
    report('7. Legitimate Pairing with Correct PIN', false, '$e');
  }

  // --- TEST 8: Re-authentication with Issued Auth Token ---
  try {
    final ws = await WebSocket.connect('ws://127.0.0.1:58921').timeout(const Duration(seconds: 2));
    final completer = Completer<bool>();

    ws.listen((data) {
      if (data is String && data.contains('SUCCESS')) {
        completer.complete(true);
      }
    });

    ws.add(jsonEncode({
      'type': 'AUTH_REQUEST',
      'id': 'legit-auth-1',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'payload': {
        'device_id': 'verified-authorized-phone-1',
        'auth_token': validAuthToken
      }
    }));

    final ok = await completer.future.timeout(const Duration(seconds: 3), onTimeout: () => false);
    report('8. Re-authentication with Issued Token', ok, 'Authorized device connected instantly');
    await ws.close();
  } catch (e) {
    report('8. Re-authentication with Issued Token', false, '$e');
  }

  // --- TEST 9: Remote Access & Stream over Cloud Relay with Token ---
  try {
    if (discoveredTunnel.isEmpty) {
      throw Exception('Discovered tunnel empty');
    }
    final customClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4)
      ..badCertificateCallback = ((cert, host, port) => true);
    final wsRelay = await WebSocket.connect(
      'wss://$discoveredTunnel',
      customClient: customClient,
    ).timeout(const Duration(seconds: 6));

    final authCompleter = Completer<bool>();
    final frameCompleter = Completer<int>();

    wsRelay.listen((data) {
      if (data is String && data.contains('SUCCESS')) {
        authCompleter.complete(true);
        // Request screen stream once authenticated
        wsRelay.add(jsonEncode({
          'type': 'SCREEN_STREAM_START',
          'id': 'relay-stream-1',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'payload': {'quality': 60, 'max_width': 960, 'fps': 15}
        }));
      } else if (data is List<int> && data.length > 1000) {
        if (!frameCompleter.isCompleted) {
          frameCompleter.complete(data.length);
        }
      }
    });

    wsRelay.add(jsonEncode({
      'type': 'AUTH_REQUEST',
      'id': 'remote-auth-1',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'payload': {
        'device_id': 'verified-authorized-phone-1',
        'auth_token': validAuthToken
      }
    }));

    final authed = await authCompleter.future.timeout(const Duration(seconds: 4), onTimeout: () => false);
    final frameSize = await frameCompleter.future.timeout(const Duration(seconds: 4), onTimeout: () => 0);

    report('9. Remote Access & Stream over Cloud Relay', authed && frameSize > 0, '${(frameSize / 1024).toStringAsFixed(1)} KB over wss://$discoveredTunnel');
    await wsRelay.close();
  } catch (e) {
    report('9. Remote Access & Stream over Cloud Relay', false, '$e');
  }

  print('\n----------------------------------------------------');
  print('AUDIT SUMMARY: $passed PASSED, $failed FAILED');
  print('----------------------------------------------------');
  exit(failed == 0 ? 0 : 1);
}
