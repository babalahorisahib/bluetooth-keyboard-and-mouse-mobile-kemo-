import 'dart:io';
import 'dart:convert';
import 'dart:async';

void main() async {
  print('==================================================');
  print('   TESTING TWO-SIDED DEVICE MANAGEMENT & SYNC     ');
  print('==================================================\n');

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

  final testDeviceId = 'device-sync-test-999';
  final testPin = '179887';
  WebSocket? ws;
  String? authToken;
  final pairCompleter = Completer<bool>();
  final removeCompleter = Completer<bool>();

  try {
    ws = await WebSocket.connect('ws://127.0.0.1:58921').timeout(const Duration(seconds: 3));

    ws.listen((data) {
      if (data is String) {
        final json = jsonDecode(data);
        if (json['type'] == 'PAIR_RESPONSE') {
          if (json['payload']?['status'] == 'APPROVED') {
            authToken = json['payload']['auth_token'];
            pairCompleter.complete(true);
          } else {
            pairCompleter.complete(false);
          }
        } else if (json['type'] == 'DEVICE_REMOVED') {
          if (json['payload']?['status'] == 'REVOKED' || json['payload']?['device_id'] == testDeviceId) {
            removeCompleter.complete(true);
          }
        }
      }
    });

    ws.add(jsonEncode({
      'v': 1,
      'type': 'PAIR_REQUEST',
      'id': 'pair-test',
      'payload': {
        'device_id': testDeviceId,
        'device_name': 'Sync Test Device',
        'pin': testPin,
        'os': 'android'
      }
    }));

    final okPair = await pairCompleter.future.timeout(const Duration(seconds: 4), onTimeout: () => false);
    report('1. Pairing Test Device with PIN', okPair, 'Token: $authToken');
  } catch (e) {
    report('1. Pairing Test Device with PIN', false, '$e');
  }

  // TEST 2: Verify token in auth_store.json
  try {
    final authStore = jsonDecode(File('auth_store.json').readAsStringSync());
    final hasToken = authStore['tokens']?[testDeviceId] != null;
    report('2. Token Persisted in auth_store.json', hasToken);
  } catch (e) {
    report('2. Token Persisted in auth_store.json', false, '$e');
  }

  // TEST 3: Send REMOVE_DEVICE
  try {
    ws?.add(jsonEncode({
      'v': 1,
      'type': 'REMOVE_DEVICE',
      'id': 'rem-1',
      'payload': {
        'device_id': testDeviceId,
        'target_device_id': testDeviceId
      }
    }));

    final okRem = await removeCompleter.future.timeout(const Duration(seconds: 4), onTimeout: () => false);
    report('3. Client Sent REMOVE_DEVICE -> Server Sent DEVICE_REMOVED', okRem);
  } catch (e) {
    report('3. Client Sent REMOVE_DEVICE', false, '$e');
  }

  // Wait 300ms for disk write
  await Future.delayed(const Duration(milliseconds: 300));

  // TEST 4: Verify Token is REVOKED and DELETED from auth_store.json
  try {
    final authStore = jsonDecode(File('auth_store.json').readAsStringSync());
    final isRevoked = authStore['tokens']?[testDeviceId] == null;
    report('4. Token Permanently Revoked in auth_store.json', isRevoked);
  } catch (e) {
    report('4. Token Permanently Revoked in auth_store.json', false, '$e');
  }

  // TEST 5: Subsequent AUTH_REQUEST with old token MUST fail
  try {
    final ws2 = await WebSocket.connect('ws://127.0.0.1:58921').timeout(const Duration(seconds: 3));
    final authCompleter = Completer<bool>();

    ws2.listen((data) {
      if (data is String) {
        final json = jsonDecode(data);
        if (json['type'] == 'AUTH_RESPONSE') {
          if (json['payload']?['status'] == 'FAILED') {
            authCompleter.complete(true); // Expected failure!
          } else {
            authCompleter.complete(false);
          }
        }
      }
    });

    ws2.add(jsonEncode({
      'v': 1,
      'type': 'AUTH_REQUEST',
      'id': 'auth-fail-test',
      'payload': {
        'device_id': testDeviceId,
        'auth_token': authToken ?? 'invalid-token'
      }
    }));

    final rejected = await authCompleter.future.timeout(const Duration(seconds: 4), onTimeout: () => false);
    report('5. Reconnection with Revoked Token Rejected', rejected);
    await ws2.close();
  } catch (e) {
    report('5. Reconnection with Revoked Token Rejected', false, '$e');
  }

  print('\n--------------------------------------------------');
  print('RESULT: $passed PASSED, $failed FAILED');
  print('--------------------------------------------------');
  exit(failed == 0 ? 0 : 1);
}
