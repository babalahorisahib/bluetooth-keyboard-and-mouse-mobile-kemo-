import 'dart:io';
import 'dart:convert';
import 'dart:async';

void main() async {
  final completer = Completer<void>();
  try {
    final ws = await WebSocket.connect('ws://127.0.0.1:58921').timeout(Duration(seconds: 3));
    ws.listen((msg) {
      if (msg is String) {
        print('WS String: $msg');
        if (msg.contains('APPROVED')) {
          ws.add(jsonEncode({
            'type': 'SCREEN_STREAM_START',
            'id': '1',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'payload': {'quality': 80, 'max_width': 1280, 'fps': 5}
          }));
        }
      } else if (msg is List<int>) {
        if (msg.length > 1000 && msg[0] == 0xFF && msg[1] == 0xD8) {
          File('scratch/captured_frame.jpg').writeAsBytesSync(msg);
          print('Saved frame: ${msg.length} bytes');
          completer.complete();
        }
      }
    });

    ws.add(jsonEncode({
      'type': 'PAIR_REQUEST',
      'id': 'test-stream-auth',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'payload': {
        'device_id': 'stream-test-client',
        'device_name': 'Stream Test Phone',
        'os': 'android',
        'pin': '179887'
      }
    }));
  } catch (e) {
    print('Error: $e');
    completer.complete();
  }

  await completer.future.timeout(Duration(seconds: 5), onTimeout: () {
    print('Timed out');
  });
  exit(0);
}
