import 'dart:io';

void main() async {
  print('WebSocket methods:');
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 4);
    final ws = await WebSocket.connect(
      'wss://catalyst-myth-trials-juice.trycloudflare.com',
      customClient: client,
    );
    print('WebSocket connected: ${ws.readyState}');
    await ws.close();
  } catch (e) {
    print('Error: $e');
  }
}
