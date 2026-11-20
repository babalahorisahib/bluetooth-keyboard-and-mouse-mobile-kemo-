import 'dart:convert';

class PairedDevice {
  final String id;
  final String name;
  final String ip;
  final int port;
  final String? tunnel; // 4G Cloud Relay URL for cross-network connectivity
  final String authToken;
  final String? pin;
  final String os; // 'windows' or 'macos'
  final bool autoConnectEnabled;
  final DateTime lastConnected;

  PairedDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    this.tunnel,
    required this.authToken,
    this.pin,
    this.os = 'windows',
    this.autoConnectEnabled = true,
    DateTime? lastConnected,
  }) : lastConnected = lastConnected ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ip': ip,
        'port': port,
        'tunnel': tunnel,
        'auth_token': authToken,
        'pin': pin,
        'os': os,
        'auto_connect_enabled': autoConnectEnabled,
        'last_connected': lastConnected.toIso8601String(),
      };

  factory PairedDevice.fromJson(Map<String, dynamic> json) => PairedDevice(
        id: json['id'] as String,
        name: json['name'] as String,
        ip: json['ip'] as String,
        port: json['port'] as int,
        tunnel: json['tunnel'] as String?,
        authToken: json['auth_token'] as String,
        pin: json['pin'] as String?,
        os: json['os'] as String? ?? 'windows',
        autoConnectEnabled: json['auto_connect_enabled'] as bool? ?? true,
        lastConnected: json['last_connected'] != null
            ? DateTime.tryParse(json['last_connected'] as String) ?? DateTime.now()
            : DateTime.now(),
      );

  String serialize() => jsonEncode(toJson());

  static PairedDevice? deserialize(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is Map<String, dynamic>) {
        return PairedDevice.fromJson(map);
      }
    } catch (_) {}
    return null;
  }

  PairedDevice copyWith({
    String? id,
    String? name,
    String? ip,
    int? port,
    String? tunnel,
    String? authToken,
    String? pin,
    String? os,
    bool? autoConnectEnabled,
    DateTime? lastConnected,
  }) {
    return PairedDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      tunnel: tunnel ?? this.tunnel,
      authToken: authToken ?? this.authToken,
      pin: pin ?? this.pin,
      os: os ?? this.os,
      autoConnectEnabled: autoConnectEnabled ?? this.autoConnectEnabled,
      lastConnected: lastConnected ?? this.lastConnected,
    );
  }
}
