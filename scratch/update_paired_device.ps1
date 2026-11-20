$content = [System.IO.File]::ReadAllText("mobile\lib\models\paired_device.dart")

$oldDef = @"
  final String authToken;
  final String os; // 'windows' or 'macos'
  final DateTime lastConnected;

  PairedDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    this.tunnel,
    required this.authToken,
    this.os = 'windows',
    DateTime? lastConnected,
  }) : lastConnected = lastConnected ?? DateTime.now();
"@

$newDef = @"
  final String authToken;
  final String? pin;
  final String os; // 'windows' or 'macos'
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
    DateTime? lastConnected,
  }) : lastConnected = lastConnected ?? DateTime.now();
"@

$content = $content.Replace($oldDef, $newDef)

$oldJson = @"
        'tunnel': tunnel,
        'auth_token': authToken,
        'os': os,
"@

$newJson = @"
        'tunnel': tunnel,
        'auth_token': authToken,
        'pin': pin,
        'os': os,
"@

$content = $content.Replace($oldJson, $newJson)

$oldFromJson = @"
        tunnel: json['tunnel'] as String?,
        authToken: json['auth_token'] as String,
        os: json['os'] as String? ?? 'windows',
"@

$newFromJson = @"
        tunnel: json['tunnel'] as String?,
        authToken: json['auth_token'] as String,
        pin: json['pin'] as String?,
        os: json['os'] as String? ?? 'windows',
"@

$content = $content.Replace($oldFromJson, $newFromJson)

$oldCopy = @"
    String? tunnel,
    String? authToken,
    String? os,
    DateTime? lastConnected,
  }) {
    return PairedDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      tunnel: tunnel ?? this.tunnel,
      authToken: authToken ?? this.authToken,
      os: os ?? this.os,
      lastConnected: lastConnected ?? this.lastConnected,
    );
  }
"@

$newCopy = @"
    String? tunnel,
    String? authToken,
    String? pin,
    String? os,
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
      lastConnected: lastConnected ?? this.lastConnected,
    );
  }
"@

$content = $content.Replace($oldCopy, $newCopy)

[System.IO.File]::WriteAllText("mobile\lib\models\paired_device.dart", $content)
Write-Output "Updated paired_device.dart"
