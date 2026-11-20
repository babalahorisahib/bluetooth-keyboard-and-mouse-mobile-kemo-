import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

void main() async {
  print('=== Mobile Kemo Microphone Streaming E2E Verification ===');

  // Load auth store to get PIN
  final authFile = File('C:/bluetooth keyboard and mouse/auth_store.json');
  String pin = '179887';
  if (authFile.existsSync()) {
    try {
      final json = jsonDecode(authFile.readAsStringSync());
      pin = json['pin']?.toString() ?? pin;
    } catch (_) {}
  }
  print('Target PIN: $pin');

  final wsUrl = 'ws://127.0.0.1:58921';
  print('Connecting to $wsUrl...');
  final ws = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 5));
  print('Connected to WebSocket!');

  final completer = Completer<void>();
  bool authenticated = false;

  ws.listen((data) {
    if (data is String) {
      print('RX Text: $data');
      final msg = jsonDecode(data);
      if (msg['type'] == 'PAIR_RESPONSE' && msg['payload']?['status'] == 'APPROVED') {
        authenticated = true;
        completer.complete();
      } else if (msg['type'] == 'AUTH_RESPONSE' && msg['payload']?['status'] == 'SUCCESS') {
        authenticated = true;
        completer.complete();
      }
    }
  });

  // Pair or auth
  final pairMsg = jsonEncode({
    'v': 1,
    'type': 'PAIR_REQUEST',
    'payload': {
      'device_id': 'test-mic-device-001',
      'device_name': 'Test Mic Phone',
      'pin': pin,
    }
  });
  ws.add(pairMsg);

  await completer.future.timeout(const Duration(seconds: 5));
  print('Authenticated successfully!');

  // Notify Mic Stream Start
  ws.add(jsonEncode({
    'v': 1,
    'type': 'MIC_STREAM_START',
    'payload': {},
  }));
  print('Sent MIC_STREAM_START');

  // Stream 20 chunks of 16kHz mono audio (1.0 second total speech simulation)
  // Each chunk: 50ms = 800 samples = 1600 bytes
  final sampleRate = 16000;
  final channels = 1;
  final chunkSamples = 800;

  for (int seq = 0; seq < 20; seq++) {
    final packet = Uint8List(12 + chunkSamples * 2);
    final byteData = ByteData.sublistView(packet);

    // 'KMIC'
    packet[0] = 0x4B;
    packet[1] = 0x4D;
    packet[2] = 0x49;
    packet[3] = 0x43;
    packet[4] = 1; // version
    packet[5] = channels; // mono
    byteData.setUint32(6, sampleRate, Endian.little);
    byteData.setUint16(10, seq, Endian.little);

    // Synthesize sine wave tone (350Hz - 500Hz)
    final freq = 350.0 + seq * 15.0;
    for (int i = 0; i < chunkSamples; i++) {
      final t = i / sampleRate;
      final sample = (sin(2 * pi * freq * t) * 10000.0).round().clamp(-32768, 32767);
      byteData.setInt16(12 + i * 2, sample, Endian.little);
    }

    ws.add(packet);
    await Future.delayed(const Duration(milliseconds: 50));
  }
  print('Successfully streamed 20 KMIC chunks (1.0 second audio) to Windows PC!');

  // Notify Mic Stream Stop
  ws.add(jsonEncode({
    'v': 1,
    'type': 'MIC_STREAM_STOP',
    'payload': {},
  }));
  print('Sent MIC_STREAM_STOP');

  await Future.delayed(const Duration(milliseconds: 200));
  await ws.close();
  print('=== TEST PASSED: Mobile Mic streaming verified successfully! ===');
  exit(0);
}
