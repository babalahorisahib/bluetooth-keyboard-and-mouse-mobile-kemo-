import 'dart:async';
import 'package:multicast_dns/multicast_dns.dart';

class DiscoveredServer {
  final String name;
  final String host;
  final int port;
  final String os;

  DiscoveredServer({
    required this.name,
    required this.host,
    required this.port,
    this.os = 'windows',
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredServer &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          port == other.port;

  @override
  int get hashCode => host.hashCode ^ port.hashCode;
}

class MdnsDiscovery {
  static const String serviceType = '_keylink._tcp.local';

  static Stream<DiscoveredServer> discover({Duration timeout = const Duration(seconds: 4)}) async* {
    final client = MDnsClient();
    try {
      await client.start();
      final seen = <String>{};

      await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(serviceType),
      )) {
        await for (final SrvResourceRecord srv in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        )) {
          await for (final IPAddressResourceRecord ip in client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
          )) {
            final key = '${ip.address.address}:${srv.port}';
            if (!seen.contains(key)) {
              seen.add(key);
              yield DiscoveredServer(
                name: ptr.domainName.split('.').first,
                host: ip.address.address,
                port: srv.port,
              );
            }
          }
        }
      }
    } catch (_) {
      // Graceful fallback if mDNS fails or permissions blocked
    } finally {
      client.stop();
    }
  }
}
