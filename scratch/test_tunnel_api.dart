import 'dart:io';

void main() async {
  print('Connecting to api.trycloudflare.com...');
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    final req = await client.postUrl(Uri.parse('https://api.trycloudflare.com/tunnel'));
    final res = await req.close();
    print('Response status: ${res.statusCode}');
    final body = await res.transform(SystemEncoding().decoder).join();
    print('Response body: $body');
  } catch (e) {
    print('Error: $e');
  }
}
