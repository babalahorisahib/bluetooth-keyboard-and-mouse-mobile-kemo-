import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

void main() async {
  print('==================================================');
  print('     TESTING REAL-TIME AUDIO STREAMING PIPELINE   ');
  print('==================================================');

  // Read saved auth token or pin
  final authStoreFile = File('c:\\bluetooth keyboard and mouse\\auth_store.json');
  String? pin;
  if (authStoreFile.existsSync()) {
    try {
      final json = jsonDecode(authStoreFile.readAsStringSync());
      pin = json['pin']?.toString();
    } catch (_) {}
  }
  pin ??= '179887';
  print('Using PIN: $pin');

  final ws = await WebSocket.connect('ws://127.0.0.1:58921');
  print('[PASS] Connected to MobileKemo WebSocket server on port 58921');

  final completer = Completer<void>();
  int audioPacketsCount = 0;
  int totalPcmBytes = 0;
  int detectedSampleRate = 0;
  int detectedChannels = 0;
  bool nonSilentAudioReceived = false;

  ws.listen((dynamic data) {
    if (data is String) {
      final msg = jsonDecode(data);
      final type = msg['type'];
      print('Received Text Message: $type');

      if (type == 'PAIR_RESPONSE') {
        final status = msg['payload']['status'];
        print('Pair response status: $status');
        if (status == 'APPROVED') {
          // Send AUDIO_STREAM_START
          final audioStartMsg = jsonEncode({
            'v': 1,
            'type': 'AUDIO_STREAM_START',
            'payload': {},
          });
          ws.add(audioStartMsg);
          print('[SENT] AUDIO_STREAM_START command');

          // Trigger a Windows beep sound in parallel to produce audio
          Process.run('powershell', ['-Command', '[Console]::Beep(1000, 400)']);
        }
      }
    } else if (data is List<int>) {
      final bytes = Uint8List.fromList(data);
      if (bytes.length >= 12 &&
          bytes[0] == 0x4B &&
          bytes[1] == 0x41 &&
          bytes[2] == 0x55 &&
          bytes[3] == 0x44) {
        // 'KAUD' magic header!
        audioPacketsCount++;
        final version = bytes[4];
        final channels = bytes[5];
        final bd = ByteData.sublistView(bytes);
        final sampleRate = bd.getUint32(6, Endian.little);
        final seq = bd.getUint16(10, Endian.little);
        final pcm = bytes.sublist(12);

        detectedSampleRate = sampleRate;
        detectedChannels = channels;
        totalPcmBytes += pcm.length;

        // Check if there are non-zero samples (real audio playing)
        for (int i = 0; i < pcm.length; i += 2) {
          final sample = bd.getInt16(12 + i, Endian.little);
          if (sample.abs() > 50) {
            nonSilentAudioReceived = true;
          }
        }

        if (audioPacketsCount % 10 == 0 || audioPacketsCount == 1) {
          print('  [AUDIO PACKET #$audioPacketsCount] ver=$version ch=$channels rate=$sampleRate seq=$seq pcm_bytes=${pcm.length} non_silent=$nonSilentAudioReceived');
        }

        if (audioPacketsCount >= 25 && nonSilentAudioReceived && !completer.isCompleted) {
          completer.complete();
        }
      }
    }
  });

  // Send PAIR_REQUEST to authenticate
  final pairMsg = jsonEncode({
    'v': 1,
    'type': 'PAIR_REQUEST',
    'id': 'test-audio-client-1',
    'payload': {
      'device_id': 'audio-tester',
      'device_name': 'Audio Tester',
      'os': 'android',
      'pin': pin,
    },
  });
  ws.add(pairMsg);

  try {
    await completer.future.timeout(const Duration(seconds: 8));
    print('\n--------------------------------------------------');
    print('AUDIO STREAMING VERIFICATION RESULT:');
    print('  - Total audio packets captured: $audioPacketsCount');
    print('  - Total PCM payload received: $totalPcmBytes bytes');
    print('  - Sample Rate: $detectedSampleRate Hz');
    print('  - Channels: $detectedChannels (Stereo)');
    print('  - Non-silent system sound detected: $nonSilentAudioReceived');
    print('  [SUCCESS] Real-time audio streaming pipeline fully verified!');
    print('--------------------------------------------------');
  } catch (e) {
    print('\n[TIMEOUT/FAIL] Expected audio packets within timeout. Received: $audioPacketsCount packets');
  } finally {
    // Send AUDIO_STREAM_STOP
    try {
      ws.add(jsonEncode({'v': 1, 'type': 'AUDIO_STREAM_STOP', 'payload': {}}));
      await Future.delayed(const Duration(milliseconds: 100));
      await ws.close();
    } catch (_) {}
  }
}
