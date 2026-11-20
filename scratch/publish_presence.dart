import 'dart:convert';
import 'dart:io';

void main() async {
  final tunnelFile = File('tunnel_active.txt');
  final tunnelUrl = tunnelFile.readAsStringSync().trim().replaceAll('https://', '').replaceAll('http://', '');
  final nowTs = 2000000000; // Future timestamp so it supersedes any old cached messages

  final payload = jsonEncode({
    'name': 'WASEEM',
    'ip': '192.168.1.101',
    'port': 58921,
    'tunnel': tunnelUrl,
    'ts': nowTs,
  });

  final client = HttpClient()..badCertificateCallback = (c, h, p) => true;
  final req = await client.postUrl(Uri.parse('https://ntfy.sh/kemo_sync_waseem'));
  req.headers.contentType = ContentType.text;
  req.write(payload);
  final resp = await req.close();
  print('kemo_sync_waseem response: ${resp.statusCode}');
}
