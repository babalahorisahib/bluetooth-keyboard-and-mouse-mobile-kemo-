import 'dart:io';

void main() async {
  final host = 'size-manuals-repository-july.trycloudflare.com';
  final sw = Stopwatch()..start();
  final ips = await InternetAddress.lookup(host);
  print('DNS lookup: ${sw.elapsedMilliseconds} ms -> ${ips.map((a) => a.address).toList()}');
  sw.reset();
  final s = await Socket.connect(host, 443, timeout: const Duration(seconds: 10));
  print('TCP connect: ${sw.elapsedMilliseconds} ms');
  sw.reset();
  final sec = await SecureSocket.secure(s, host: host);
  print('TLS handshake: ${sw.elapsedMilliseconds} ms');
  sw.reset();
  await sec.close();
  print('Done!');
}
