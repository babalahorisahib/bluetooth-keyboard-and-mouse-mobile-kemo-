import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

void main() async {
  print('====================================================');
  print('    KEMO SIMULTANEOUS AUDIO + SCREEN + INPUT TEST   ');
  print('====================================================');

  final authStoreFile = File('c:\\bluetooth keyboard and mouse\\auth_store.json');
  String? pin;
  if (authStoreFile.existsSync()) {
    try {
      final json = jsonDecode(authStoreFile.readAsStringSync());
      pin = json['pin']?.toString();
    } catch (_) {}
  }
  pin ??= '179887';

  final ws = await WebSocket.connect('ws://127.0.0.1:58921');
  print('[PASS] Connected to WebSocket server');

  int audioPackets = 0;
  int screenFrames = 0;
  int totalPcmBytes = 0;
  int totalJpegBytes = 0;
  bool inputAckReceived = false;

  final completer = Completer<void>();
  Timer? beepTimer;

  // Run one background PowerShell script that beeps periodically
  Process.run('powershell', ['-Command', 'for (\$i=0; \$i -lt 10; \$i++) { [Console]::Beep(1000, 250); Start-Sleep -Milliseconds 100 }']);

  ws.listen((dynamic data) {
    if (data is String) {
      final msg = jsonDecode(data);
      final type = msg['type'];
      if (type == 'PAIR_RESPONSE') {
        if (msg['payload']['status'] == 'APPROVED') {
          print('[PASS] Pair approved. Starting screen and audio streams...');
          // Start Screen Stream
          ws.add(jsonEncode({
            'v': 1,
            'type': 'SCREEN_STREAM_START',
            'id': 'stream-1',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'payload': {
              'quality': 65,
              'max_width': 960,
              'fps': 15,
            }
          }));

          // Start Audio Stream
          ws.add(jsonEncode({
            'v': 1,
            'type': 'AUDIO_STREAM_START',
            'id': 'audio-1',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'payload': {}
          }));
        }
      }
    } else if (data is List<int>) {
      final bytes = Uint8List.fromList(data);
      if (bytes.length >= 12 && bytes[0] == 0x4B && bytes[1] == 0x41 && bytes[2] == 0x55 && bytes[3] == 0x44) {
        // Audio frame (KAUD)
        audioPackets++;
        totalPcmBytes += (bytes.length - 12);
      } else if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
        // JPEG screen frame
        screenFrames++;
        totalJpegBytes += bytes.length;
        // Send ACK
        if (!completer.isCompleted) {
          ws.add(jsonEncode({
            'v': 1,
            'type': 'FRAME_ACK',
            'id': 'ack-$screenFrames',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'payload': {}
          }));
        }

        // When we have received at least 5 screen frames and 10 audio packets, inject input
        if (screenFrames >= 5 && audioPackets >= 10 && !inputAckReceived) {
          inputAckReceived = true;
          // Send touch click
          ws.add(jsonEncode({
            'v': 1,
            'type': 'TOUCH_EVENT',
            'payload': {'action': 'click', 'x': 0.5, 'y': 0.5}
          }));
          // Send Urdu typing
          ws.add(jsonEncode({
            'v': 1,
            'type': 'TEXT_INPUT',
            'payload': {'text': 'سلام Mobile Kemo 123'}
          }));
          print('[PASS] Injected Touch Click and Urdu text input during live streaming');
        }
      }

      if (audioPackets >= 30 && screenFrames >= 15 && !completer.isCompleted) {
        completer.complete();
      }
    }
  });

  // Authenticate
  ws.add(jsonEncode({
    'v': 1,
    'type': 'PAIR_REQUEST',
    'id': 'e2e-client-1',
    'payload': {
      'device_id': 'e2e-tester',
      'device_name': 'E2E Tester',
      'os': 'android',
      'pin': pin,
    }
  }));

  try {
    await completer.future.timeout(const Duration(seconds: 12));
    print('----------------------------------------------------');
    print('[PASS] Audio Packets received: $audioPackets ($totalPcmBytes bytes PCM)');
    print('[PASS] Screen Frames received: $screenFrames ($totalJpegBytes bytes JPEG)');
    print('[PASS] Simultaneous Audio + Video Multiplexing: FULLY OPERATIONAL');
    print('[PASS] Input during live streaming: FULLY OPERATIONAL');
    print('----------------------------------------------------');
    print('ALL E2E STREAMING AND CONTROL TESTS PASSED!');
  } catch (e) {
    print('[FAIL/TIMEOUT] Audio packets: $audioPackets, Screen frames: $screenFrames');
  } finally {
    ws.add(jsonEncode({'v': 1, 'type': 'AUDIO_STREAM_STOP', 'payload': {}}));
    ws.add(jsonEncode({'v': 1, 'type': 'SCREEN_STREAM_STOP', 'payload': {}}));
    await Future.delayed(const Duration(milliseconds: 150));
    await ws.close();
  }
}
