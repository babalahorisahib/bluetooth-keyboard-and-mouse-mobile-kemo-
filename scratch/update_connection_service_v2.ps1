$content = [System.IO.File]::ReadAllText("mobile\lib\services\connection_service.dart")

$oldMethods = @'
  /// Connect via QR code scan or manual IP (Wi-Fi or 4G Cloud Tunnel)
  Future<bool> pairWithServer({
'@

$newCode = @'
  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;

  static String normalizeDeviceName(String name) {
    return name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static String deriveSecureTopic(String normalizedName, String pin) {
    final cleanPin = pin.trim();
    final hash = sha256.convert(utf8.encode('kemo_rendezvous:$normalizedName:$cleanPin')).toString();
    return 'kemo_v2_${hash.substring(0, 20)}';
  }

  static List<String> getPresenceTopics(String serverName, String? pin) {
    final norm = normalizeDeviceName(serverName);
    final topics = <String>[];
    if (pin != null && pin.trim().isNotEmpty) {
      topics.add(deriveSecureTopic(norm, pin));
    }
    if (norm.isNotEmpty) {
      topics.add('kemo_sync_$norm');
    }
    return topics;
  }

  static String? validateTunnelUrl(dynamic rawTunnel) {
    if (rawTunnel == null) return null;
    final str = rawTunnel.toString().trim().replaceFirst(RegExp(r'^(https?|wss?)://'), '').replaceAll(RegExp(r'/+$'), '');
    if (str.isEmpty) return null;
    if (RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9\-]*(\.[a-zA-Z0-9\-]+)+$').hasMatch(str)) {
      return str;
    }
    return null;
  }

  /// Discovers the latest verified presence information (IP, port, tunnel)
  Future<Map<String, dynamic>?> _queryPresence(String serverName, String? pin) async {
    final topics = getPresenceTopics(serverName, pin);
    for (final topic in topics) {
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
        final req = await client.getUrl(Uri.parse('https://ntfy.sh/$topic/json?poll=1')).timeout(const Duration(seconds: 3));
        final resp = await req.close();
        if (resp.statusCode == 200) {
          final body = await resp.transform(utf8.decoder).join();
          client.close();
          final lines = body.split('\n');

          Map<String, dynamic>? bestMsg;
          int highestTs = -1;

          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) continue;
            try {
              final parsed = jsonDecode(trimmed);
              if (parsed is Map && parsed['message'] != null) {
                final msgStr = parsed['message'].toString();
                Map<String, dynamic>? data;
                try {
                  data = jsonDecode(msgStr) as Map<String, dynamic>;
                } catch (_) {
                  final cleaned = msgStr.trim().replaceAll(RegExp(r'^\{|\}$'), '');
                  final parts = cleaned.split(',');
                  final map = <String, dynamic>{};
                  for (final part in parts) {
                    final kv = part.split(':');
                    if (kv.length >= 2) {
                      map[kv[0].trim()] = kv.sublist(1).join(':').trim();
                    }
                  }
                  if (map.containsKey('ip')) data = map;
                }

                if (data != null && data['ip'] != null) {
                  final ts = int.tryParse(data['ts']?.toString() ?? '0') ?? 0;
                  if (ts >= highestTs) {
                    highestTs = ts;
                    bestMsg = data;
                  }
                }
              }
            } catch (_) {}
          }

          if (bestMsg != null) {
            return bestMsg;
          }
        } else {
          client.close();
        }
      } catch (_) {}
    }
    return null;
  }

  /// Connect via QR code scan or manual IP (Wi-Fi or 4G Cloud Tunnel)
  Future<bool> pairWithServer({
'@

$content = $content.Replace($oldMethods, $newCode)

$oldPairAndAuto = @'  /// Connect via QR code scan or manual IP (Wi-Fi or 4G Cloud Tunnel)
  Future<bool> pairWithServer({
    required String host,
    required int port,
    required String pin,
    String? serverName,
    String? tunnel,
  }) async {
    _connectionMode = ConnectionMode.qrWifi;
    _lastError = null;

    bool ok = false;
    String connectedHost = host;
    int connectedPort = port;

    final String cleanHost = host.trim().replaceFirst(RegExp(r'^(https?|wss?)://'), '');
    final bool hostIsDomain = RegExp(r'[a-zA-Z]').hasMatch(cleanHost) && cleanHost.contains('.');

    if (hostIsDomain) {
      connectedHost = cleanHost;
      connectedPort = 443;
      ok = await _wifiTransport.connect(cleanHost, 443);
    } else {
      // 1. Try local IP first (fastest on Wi-Fi)
      ok = await _wifiTransport.connect(host, port);

      // 2. If direct LAN failed (e.g. mobile on 4G cellular data or different network), connect via Cloud Tunnel!
      if (!ok && tunnel != null && tunnel.isNotEmpty) {
        final cleanTunnel = tunnel.trim().replaceFirst(RegExp(r'^(https?|wss?)://'), '');
        connectedHost = cleanTunnel;
        connectedPort = 443;
        ok = await _wifiTransport.connect(cleanTunnel, 443);
      }

      // 3. Fallback: Query live cloud presence for updated tunnel URL
      if (!ok && serverName != null && serverName.isNotEmpty) {
        final sanitizedName = serverName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        try {
          final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
          final res = await client.getUrl(Uri.parse('https://ntfy.sh/kemo_sync_$sanitizedName/json?poll=1')).timeout(const Duration(seconds: 2));
          final resp = await res.close();
          if (resp.statusCode == 200) {
            final body = await resp.transform(utf8.decoder).join();
            for (final line in body.split('\n').reversed) {
              if (line.trim().isEmpty) continue;
              final parsed = jsonDecode(line);
              if (parsed is Map && parsed['message'] != null) {
                final msg = parsed['message'].toString();
                if (msg.contains('.trycloudflare.com')) {
                  final reg = RegExp(r'([a-zA-Z0-9\-]+\.trycloudflare\.com)');
                  final m = reg.firstMatch(msg);
                  if (m != null) {
                    final freshTunnel = m.group(1)!;
                    connectedHost = freshTunnel;
                    connectedPort = 443;
                    ok = await _wifiTransport.connect(freshTunnel, 443);
                    if (ok) break;
                  }
                }
              }
            }
          }
          client.close();
        } catch (_) {}
      }
    }

    if (!ok) {
      _lastError = 'Could not connect to PC or 4G Cloud Relay. Check PIN and Internet connection.';
      notifyListeners();
      return false;
    }

    _activeDevice = PairedDevice(
      id: const Uuid().v4(),
      name: serverName ?? 'KeyLink PC',
      ip: connectedHost,
      port: connectedPort,
      tunnel: tunnel,
      authToken: '',
      pin: pin,
    );

    final req = KeyLinkMessage.pairRequest(
      deviceId: _deviceId,
      deviceName: _deviceName,
      os: Platform.operatingSystem,
      pin: pin,
    );
    _wifiTransport.send(req);
    return true;
  }

  /// Connect to an existing paired device using stored auth token (Wi-Fi or 4G Cloud Relay)
  Future<bool> connectToPairedDevice(PairedDevice device) async {
    return await autoConnect(targetDevice: device);
  }

  /// Universal Multi-Tier Auto-Connect across Local Wi-Fi, 4G Data, and Internet Relay
  Future<bool> autoConnect({PairedDevice? targetDevice}) async {
    _connectionMode = ConnectionMode.qrWifi;
    _lastError = null;

    final device = targetDevice ?? _activeDevice ?? (_pairedDevices.isNotEmpty ? _pairedDevices.first : null);
    if (device == null) {
      _lastError = 'No paired computer found. Scan QR code once to pair.';
      notifyListeners();
      return false;
    }

    _activeDevice = device;
    _status = ConnectionStatus.connecting;
    notifyListeners();

    // Priority 1: Try direct local connection first (instant if on same Wi-Fi)
    bool ok = await _wifiTransport.connect(device.ip, device.port);
    if (ok) {
      if (device.authToken.isNotEmpty) {
        _wifiTransport.send(KeyLinkMessage.authRequest(deviceId: _deviceId, authToken: device.authToken));
      }
      return true;
    }

    // Priority 2: If on different network or IP changed, query live presence from secure ntfy.sh rendezvous
    final sanitizedName = device.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final topicsToTry = <String>[];
    if (device.pin != null && device.pin!.isNotEmpty) {
      final hash = sha256.convert(utf8.encode('kemo_rendezvous:$sanitizedName:${device.pin}')).toString();
      topicsToTry.add('kemo_v2_${hash.substring(0, 20)}');
    }
    topicsToTry.add('kemo_sync_$sanitizedName');

    PairedDevice currentDevice = device;

    for (final topic in topicsToTry) {
      if (ok) break;
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
        final res = await client.getUrl(Uri.parse('https://ntfy.sh/$topic/json?poll=1')).timeout(const Duration(seconds: 2));
        final resp = await res.close();
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final lines = body.split('\n');
        for (final line in lines.reversed) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          try {
            final parsed = jsonDecode(trimmed);
            if (parsed is Map && parsed['message'] != null) {
              final msgStr = parsed['message'].toString();
              Map<String, dynamic>? data;
              try {
                data = jsonDecode(msgStr) as Map<String, dynamic>;
              } catch (_) {
                final cleaned = msgStr.trim().replaceAll(RegExp(r'^\{|\}$'), '');
                final parts = cleaned.split(',');
                final map = <String, dynamic>{};
                for (final part in parts) {
                  final kv = part.split(':');
                  if (kv.length >= 2) {
                    map[kv[0].trim()] = kv.sublist(1).join(':').trim();
                  }
                }
                if (map.containsKey('ip')) data = map;
              }

              if (data != null && data['ip'] != null) {
                final newIp = data['ip'].toString();
                final newPort = int.tryParse(data['port'].toString()) ?? 58921;
                final newTunnel = data['tunnel']?.toString();

                currentDevice = currentDevice.copyWith(
                  ip: newIp,
                  port: newPort,
                  tunnel: (newTunnel != null && newTunnel.isNotEmpty) ? newTunnel : currentDevice.tunnel,
                );
                _saveOrUpdatePairedDevice(currentDevice);
                _activeDevice = currentDevice;

                // If on same Wi-Fi with new IP:
                if (newIp != device.ip) {
                  ok = await _wifiTransport.connect(newIp, newPort);
                  if (ok) {
                    if (currentDevice.authToken.isNotEmpty) {
                      _wifiTransport.send(KeyLinkMessage.authRequest(deviceId: _deviceId, authToken: currentDevice.authToken));
                    }
                    return true;
                  }
                }
                break;
              }
            }
          } catch (_) {}
        }
      }
        client.close();
      } catch (_) {}
    }

    // Priority 3: Connect via Secure Cloud Relay Tunnel (works across 4G, hotspots, and remote networks)
    if (currentDevice.tunnel != null && currentDevice.tunnel!.isNotEmpty) {
      final cleanTunnel = currentDevice.tunnel!.trim().replaceFirst(RegExp(r'^(https?|wss?)://'), '');
      ok = await _wifiTransport.connect(cleanTunnel, 443);
      if (ok) {
        if (currentDevice.authToken.isNotEmpty) {
          _wifiTransport.send(KeyLinkMessage.authRequest(deviceId: _deviceId, authToken: currentDevice.authToken));
        }
        return true;
      }
    }

    _lastError = 'Could not reach ${currentDevice.name} on Local Wi-Fi or 4G Cloud Relay. Ensure Mobile Kemo is running on PC.';
    notifyListeners();
    return false;
  }'@

$newPairAndAuto = @'  /// Connect via QR code scan or manual IP (Wi-Fi or 4G Cloud Tunnel)
  Future<bool> pairWithServer({
    required String host,
    required int port,
    required String pin,
    String? serverName,
    String? tunnel,
  }) async {
    if (_isConnecting) return false;
    _isConnecting = true;
    _connectionMode = ConnectionMode.qrWifi;
    _lastError = null;

    try {
      bool ok = false;
      String connectedHost = host;
      int connectedPort = port;

      final String cleanHost = host.trim().replaceFirst(RegExp(r'^(https?|wss?)://'), '');
      final bool hostIsDomain = RegExp(r'[a-zA-Z]').hasMatch(cleanHost) && cleanHost.contains('.');

      if (hostIsDomain) {
        connectedHost = cleanHost;
        connectedPort = 443;
        ok = await _wifiTransport.connect(cleanHost, 443);
      } else {
        // 1. Try local IP first (fastest on Wi-Fi)
        ok = await _wifiTransport.connect(host, port);

        // 2. If direct LAN failed, try provided tunnel
        final validProvidedTunnel = validateTunnelUrl(tunnel);
        if (!ok && validProvidedTunnel != null) {
          connectedHost = validProvidedTunnel;
          connectedPort = 443;
          ok = await _wifiTransport.connect(validProvidedTunnel, 443);
        }

        // 3. Fallback: Query live cloud presence for updated tunnel URL using canonical topics!
        if (!ok && serverName != null && serverName.isNotEmpty) {
          final presence = await _queryPresence(serverName, pin);
          if (presence != null) {
            final freshTunnel = validateTunnelUrl(presence['tunnel']);
            if (freshTunnel != null) {
              connectedHost = freshTunnel;
              connectedPort = 443;
              ok = await _wifiTransport.connect(freshTunnel, 443);
            }
          }
        }
      }

      if (!ok) {
        _lastError = 'Could not connect to ${serverName ?? "PC"} via Wi-Fi or Cloud Relay. Check that Mobile Kemo is running on PC and device has internet.';
        notifyListeners();
        return false;
      }

      _activeDevice = PairedDevice(
        id: const Uuid().v4(),
        name: serverName ?? 'KeyLink PC',
        ip: connectedHost,
        port: connectedPort,
        tunnel: tunnel,
        authToken: '',
        pin: pin,
      );

      final req = KeyLinkMessage.pairRequest(
        deviceId: _deviceId,
        deviceName: _deviceName,
        os: Platform.operatingSystem,
        pin: pin,
      );
      _wifiTransport.send(req);
      return true;
    } finally {
      _isConnecting = false;
    }
  }

  /// Connect to an existing paired device using stored auth token (Wi-Fi or 4G Cloud Relay)
  Future<bool> connectToPairedDevice(PairedDevice device) async {
    return await autoConnect(targetDevice: device);
  }

  /// Universal Multi-Tier Auto-Connect across Local Wi-Fi, 4G Data, and Internet Relay
  Future<bool> autoConnect({PairedDevice? targetDevice}) async {
    if (_isConnecting) return false;
    _isConnecting = true;
    _connectionMode = ConnectionMode.qrWifi;
    _lastError = null;

    try {
      final device = targetDevice ?? _activeDevice ?? (_pairedDevices.isNotEmpty ? _pairedDevices.first : null);
      if (device == null) {
        _lastError = 'No paired computer found. Scan QR code once to pair.';
        notifyListeners();
        return false;
      }

      _activeDevice = device;
      _status = ConnectionStatus.connecting;
      notifyListeners();

      // Priority 1: Try direct local connection first (instant if on same Wi-Fi)
      bool ok = await _wifiTransport.connect(device.ip, device.port);
      if (ok) {
        if (device.authToken.isNotEmpty) {
          _wifiTransport.send(KeyLinkMessage.authRequest(deviceId: _deviceId, authToken: device.authToken));
        }
        return true;
      }

      // Priority 2: Query latest live endpoint from presence rendezvous (picks newest timestamp)
      PairedDevice currentDevice = device;
      final presence = await _queryPresence(device.name, device.pin);
      if (presence != null) {
        final newIp = presence['ip']?.toString();
        final newPort = int.tryParse(presence['port']?.toString() ?? '') ?? 58921;
        final validTunnel = validateTunnelUrl(presence['tunnel']);

        if (newIp != null && newIp.isNotEmpty) {
          currentDevice = currentDevice.copyWith(
            ip: newIp,
            port: newPort,
            tunnel: validTunnel ?? currentDevice.tunnel,
          );
          _saveOrUpdatePairedDevice(currentDevice);
          _activeDevice = currentDevice;

          // If on same Wi-Fi with new IP:
          if (newIp != device.ip) {
            ok = await _wifiTransport.connect(newIp, newPort);
            if (ok) {
              if (currentDevice.authToken.isNotEmpty) {
                _wifiTransport.send(KeyLinkMessage.authRequest(deviceId: _deviceId, authToken: currentDevice.authToken));
              }
              return true;
            }
          }
        }
      }

      // Priority 3: Connect via Secure Cloud Relay Tunnel (works across 4G, hotspots, and remote networks)
      final tunnelToTry = validateTunnelUrl(currentDevice.tunnel);
      if (tunnelToTry != null) {
        ok = await _wifiTransport.connect(tunnelToTry, 443);
        if (ok) {
          if (currentDevice.authToken.isNotEmpty) {
            _wifiTransport.send(KeyLinkMessage.authRequest(deviceId: _deviceId, authToken: currentDevice.authToken));
          }
          return true;
        }
      }

      // Granular diagnostic failure message
      if (presence == null) {
        _lastError = 'Cannot reach ${currentDevice.name}. Local Wi-Fi failed and presence service unreachable. Ensure Mobile Kemo is running on PC.';
      } else if (tunnelToTry != null) {
        _lastError = 'Local Wi-Fi unreachable and Cloud Relay tunnel failed. Ensure PC has internet access.';
      } else {
        _lastError = 'Could not reach ${currentDevice.name} on Local Wi-Fi or Cloud Relay. Check PC connection.';
      }
      notifyListeners();
      return false;
    } finally {
      _isConnecting = false;
    }
  }'@

$content = $content.Replace($oldPairAndAuto, $newPairAndAuto)

[System.IO.File]::WriteAllText("mobile\lib\services\connection_service.dart", $content)
Write-Output "Successfully updated connection_service.dart"
