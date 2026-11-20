import 'dart:io';

void main() async {
  final urls = [
    'https://trycloudflare.com',
    'https://cloudflare.com',
    'https://api.github.com',
    'https://ntfy.sh',
    'https://raw.githubusercontent.com',
  ];
  final client = HttpClient()..badCertificateCallback = (c, h, p) => true;
  for (final u in urls) {
    try {
      final req = await client.getUrl(Uri.parse(u)).timeout(const Duration(seconds: 8));
      final resp = await req.close();
      print('$u : ${resp.statusCode}');
    } catch (e) {
      print('$u : FAILED ($e)');
    }
  }
}
