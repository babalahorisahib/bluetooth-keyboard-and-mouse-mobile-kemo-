import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/paired_device.dart';
import '../models/protocol_message.dart';
import '../network/bluetooth_transport.dart';
import '../network/transport_interface.dart';
import '../network/websocket_transport.dart';

enum ConnectionMode { qrWifi, bluetooth }

class ConnectionService extends ChangeNotifier {
  static const String _keyDeviceId = 'keylink_device_id';
  static const String _keyPairedDevices = 'keylink_paired_devices';
  static const MethodChannel _bgChannel = MethodChannel('com.mobilekemo/background');

  Future<void> _acquireNativeLocks() async {
    try {
      if (Platform.isAndroid) {
        await _bgChannel.invokeMethod('acquireWakeLock');
        final pcName = _activeDevice?.name ?? 'Desktop PC';
        await _bgChannel.invokeMethod('startKeepAliveService', {'pc_name': pcName});
      }
    } catch (_) {}
  }

  Future<void> _releaseNativeLocks() async {
    try {
      if (Platform.isAndroid) {
        await _bgChannel.invokeMethod('releaseWakeLock');
        await _bgChannel.invokeMethod('stopKeepAliveService');
      }
    } catch (_) {}
  }

  late final WebSocketTransport _wifiTransport;
  late final BluetoothTransport _bluetoothTransport;
  StreamSubscription? _wifiStatusSub;
  StreamSubscription? _wifiMessageSub;
  StreamSubscription? _bluetoothStatusSub;
  StreamSubscription? _bluetoothMessageSub;
  StreamSubscription<AudioPacket>? _audioStreamSub;

  ConnectionMode _connectionMode = ConnectionMode.qrWifi;

  String _deviceId = '';
  String _deviceName = 'KeyLink Phone';
  List<PairedDevice> _pairedDevices = [];
  PairedDevice? _activeDevice;

  ConnectionStatus _status = ConnectionStatus.disconnected;
  String? _lastError;
  int _latencyMs = 0;
  bool _isAudioStreaming = false;
  bool _userMutedAudio = false;
  bool _isMicActive = false;
  Timer? _latencyPollTimer;
  Timer? _autoConnectTimer;
  final StreamController<Map<String, dynamic>> _voiceResponseController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get voiceResponseStream => _voiceResponseController.stream;

  ConnectionMode get connectionMode => _connectionMode;
  ConnectionStatus get status => _status;
  bool get isConnected => _status == ConnectionStatus.connected;
  bool get isAudioStreaming => _isAudioStreaming;
  bool get isAudioMuted => _userMutedAudio;
  bool get isMicActive => _isMicActive;
  String? get lastError => _lastError;
  int get latencyMs => _latencyMs;
  PairedDevice? get activeDevice => _activeDevice;
  List<PairedDevice> get pairedDevices => List.unmodifiable(_pairedDevices);
  String get deviceId => _deviceId;
  String get deviceName => _deviceName;
  BluetoothTransport get bluetoothTransport => _bluetoothTransport;
  Stream<Uint8List> get screenStream => _wifiTransport.screenStream;

  String get connectionMedium {
    if (_connectionMode == ConnectionMode.bluetooth) {
      return 'Bluetooth';
    }
    final host = _wifiTransport.connectedHost ?? _activeDevice?.ip ?? '';
    final lower = host.toLowerCase();
    if (lower.contains('192.168.') ||
        lower.contains('10.') ||
        lower.contains('172.') ||
        lower.contains('127.0.0.1') ||
        lower.contains('.local')) {
      return 'Local Wi-Fi';
    }
    if (lower.contains('.trycloudflare.com') ||
        lower.contains('.ngrok') ||
        lower.contains('.pinggy') ||
        lower.contains('.localhost.run') ||
        lower.contains('.loca.lt')) {
      return 'Relay (Internet / 4G)';
    }
    return 'Direct Internet';
  }

  String get connectionQuality {
    if (_status == ConnectionStatus.connecting || _status == ConnectionStatus.authenticating) {
      return 'Connecting...';
    }
    if (_status == ConnectionStatus.disconnected || _status == ConnectionStatus.error) {
      return 'Disconnected';
    }
    if (_latencyMs <= 0) return 'Connected';
    if (_latencyMs < 35) return 'Excellent (${_latencyMs}ms)';
    if (_latencyMs < 85) return 'Good (${_latencyMs}ms)';
    return 'Fair (${_latencyMs}ms)';
  }

  KeyLinkTransport get _activeTransport =>
      _connectionMode == ConnectionMode.bluetooth ? _bluetoothTransport : _wifiTransport;

  ConnectionService() {
    _wifiTransport = WebSocketTransport();
    _bluetoothTransport = BluetoothTransport();
    _wifiTransport.onReconnectRequested = () => autoConnect();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_keyDeviceId) ?? '';
    if (_deviceId.isEmpty) {
      _deviceId = const Uuid().v4();
      await prefs.setString(_keyDeviceId, _deviceId);
    }

    if (Platform.isAndroid) {
      _deviceName = 'Android Device';
    } else if (Platform.isIOS) {
      _deviceName = 'iPhone';
    } else {
      _deviceName = Platform.localHostname;
    }

    _loadPairedDevices(prefs);

    // Wi-Fi transport listeners
    _wifiStatusSub = _wifiTransport.statusStream.listen((status) {
      if (_connectionMode == ConnectionMode.qrWifi) {
        _status = status;
        if (status == ConnectionStatus.connected) {
          _acquireNativeLocks();
        } else if (status == ConnectionStatus.disconnected) {
          _releaseNativeLocks();
        }

        if (status == ConnectionStatus.authenticating &&
            _activeDevice != null &&
            _activeDevice!.authToken.isNotEmpty) {
          final req = KeyLinkMessage.authRequest(
            deviceId: _deviceId,
            authToken: _activeDevice!.authToken,
          );
          _wifiTransport.send(req);
        }
        notifyListeners();
      }
    });

    _wifiMessageSub = _wifiTransport.messageStream.listen((msg) {
      if (_connectionMode == ConnectionMode.qrWifi) {
        _handleIncomingMessage(msg);
      }
    });

    _audioStreamSub = _wifiTransport.audioStream.listen((packet) {
      if (_isAudioStreaming && Platform.isAndroid) {
        _bgChannel.invokeMethod('playAudioChunk', {
          'data': packet.pcmData,
          'sampleRate': packet.sampleRate,
          'channels': packet.channels,
        });
      }
    });

    if (Platform.isAndroid) {
      _bgChannel.setMethodCallHandler((call) async {
        if (call.method == 'onAudioMuteChanged') {
          final isMuted = (call.arguments as Map?)?['isMuted'] as bool? ?? false;
          if (isMuted) {
            stopAudioStream(userInitiated: true);
          } else {
            startAudioStream(userInitiated: true);
          }
        } else if (call.method == 'onMicChunk') {
          if (_isMicActive && isConnected) {
            final args = call.arguments as Map?;
            final data = args?['data'] as Uint8List?;
            final sampleRate = args?['sampleRate'] as int? ?? 16000;
            final channels = args?['channels'] as int? ?? 1;
            if (data != null && data.isNotEmpty) {
              _wifiTransport.sendMicChunk(data, sampleRate: sampleRate, channels: channels);
            }
          }
        } else if (call.method == 'onMicPermissionGranted') {
          if (_isMicActive) {
            startMic();
          }
        }
      });
    }

    // Bluetooth transport listeners
    _bluetoothStatusSub = _bluetoothTransport.statusStream.listen((status) {
      if (_connectionMode == ConnectionMode.bluetooth) {
        _status = status;
        notifyListeners();
      }
    });

    _bluetoothMessageSub = _bluetoothTransport.messageStream.listen((msg) {
      if (_connectionMode == ConnectionMode.bluetooth) {
        _handleIncomingMessage(msg);
      }
    });

    _latencyPollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final currentLatency = _activeTransport.latencyMs;
      if (_status == ConnectionStatus.connected && currentLatency != _latencyMs) {
        _latencyMs = currentLatency;
        notifyListeners();
      }
    });
  }

  void setConnectionMode(ConnectionMode mode) {
    if (_connectionMode != mode) {
      _connectionMode = mode;
      _status = _activeTransport.status;
      notifyListeners();
    }
  }

  void _startAutoConnectTimer() {
    _autoConnectTimer?.cancel();
    _autoConnectTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if ((_status == ConnectionStatus.disconnected || _status == ConnectionStatus.error) && !_isConnecting) {
        final target = _activeDevice ?? (_pairedDevices.isNotEmpty ? _pairedDevices.first : null);
        if (target != null && target.autoConnectEnabled) {
          autoConnect(targetDevice: target);
        }
      }
    });
  }

  void _loadPairedDevices(SharedPreferences prefs) {
    final rawList = prefs.getStringList(_keyPairedDevices) ?? [];
    _pairedDevices = rawList
        .map((str) => PairedDevice.deserialize(str))
        .whereType<PairedDevice>()
        .toList();
    if (_pairedDevices.isNotEmpty && _activeDevice == null) {
      _activeDevice = _pairedDevices.first;
    }
    notifyListeners();

    // Auto-connect on startup for authorized devices
    if (_activeDevice != null && _activeDevice!.autoConnectEnabled && _status == ConnectionStatus.disconnected) {
      autoConnect(targetDevice: _activeDevice);
    }
    _startAutoConnectTimer();
  }

  Future<void> _savePairedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = _pairedDevices.map((d) => d.serialize()).toList();
    await prefs.setStringList(_keyPairedDevices, rawList);
  }

  void _handleIncomingMessage(KeyLinkMessage msg) {
    switch (msg.type) {
      case MessageType.pairResponse:
        final status = msg.payload['status'] as String? ?? '';
        if (status == 'APPROVED') {
          final token = msg.payload['auth_token'] as String? ?? '';
          final serverName = msg.payload['server_name'] as String? ?? 'Desktop PC';
          final os = msg.payload['os'] as String? ?? 'windows';

          if (_activeDevice != null && token.isNotEmpty) {
            final updated = _activeDevice!.copyWith(
              name: serverName,
              authToken: token,
              os: os,
              lastConnected: DateTime.now(),
            );
            _saveOrUpdatePairedDevice(updated);
            _activeDevice = updated;
            _wifiTransport.markAuthenticated();
            _lastError = null;
          }
        } else {
          _lastError = 'Pairing rejected: $status';
          disconnect(reason: 'pairing_rejected');
        }
        notifyListeners();
        break;

      case MessageType.authResponse:
        final status = msg.payload['status'] as String? ?? '';
        if (status == 'SUCCESS') {
          if (_connectionMode == ConnectionMode.qrWifi) {
            _wifiTransport.markAuthenticated();
          }
          if (_activeDevice != null) {
            final updated = _activeDevice!.copyWith(lastConnected: DateTime.now());
            _saveOrUpdatePairedDevice(updated);
            _activeDevice = updated;
          }
          _lastError = null;
        } else {
          _lastError = 'Authentication failed. Please re-pair.';
          disconnect(reason: 'auth_failed');
        }
        notifyListeners();
        break;

      case MessageType.voiceResponse:
        _voiceResponseController.add(msg.payload);
        notifyListeners();
        break;

      case MessageType.disconnect:
        final reason = msg.payload['reason'] as String? ?? 'Server disconnected';
        _lastError = 'Disconnected: $reason';
        disconnect(reason: reason);
        break;

      case MessageType.deviceRemoved:
        _pairedDevices.removeWhere((d) => d.id == _activeDevice?.id);
        _activeDevice = null;
        _savePairedDevices();
        disconnect(reason: 'server_revoked_device');
        _lastError = 'Device pairing was removed by the PC user.';
        notifyListeners();
        break;

      case MessageType.serverDisconnect:
        disconnect(reason: 'server_requested_disconnect', explicitUserDisconnect: true);
        _lastError = 'Disconnected by PC user.';
        notifyListeners();
        break;

      default:
        break;
    }
  }

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
    Map<String, dynamic>? bestMsg;
    int highestTs = -1;

    for (final topic in topics) {
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 15)
          ..badCertificateCallback = (cert, host, port) => true;
        final req = await client.getUrl(Uri.parse('https://ntfy.sh/$topic/json?poll=1')).timeout(const Duration(seconds: 15));
        final resp = await req.close();
        if (resp.statusCode == 200) {
          final body = await resp.transform(utf8.decoder).join();
          client.close();
          final lines = body.split('\n');

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
                  if (map.containsKey('ip') || map.containsKey('tunnel')) data = map;
                }

                if (data != null && (data['ip'] != null || data['tunnel'] != null)) {
                  final ts = int.tryParse(data['ts']?.toString() ?? '0') ?? 0;
                  if (ts >= highestTs) {
                    highestTs = ts;
                    bestMsg = data;
                  }
                }
              }
            } catch (_) {}
          }
        } else {
          client.close();
        }
      } catch (_) {}
    }
    return bestMsg;
  }

  /// Helper to await server verification (Approved or Disconnected/Timeout)
  Future<bool> _waitForAuthentication({Duration timeout = const Duration(seconds: 10)}) async {
    if (_status == ConnectionStatus.connected) return true;
    final completer = Completer<bool>();
    late StreamSubscription sub;
    sub = _wifiTransport.statusStream.listen((status) {
      if (status == ConnectionStatus.connected) {
        if (!completer.isCompleted) completer.complete(true);
      } else if (status == ConnectionStatus.disconnected || status == ConnectionStatus.error) {
        if (!completer.isCompleted) completer.complete(false);
      }
    });

    if (_status == ConnectionStatus.connected) {
      await sub.cancel();
      return true;
    }

    final success = await completer.future.timeout(timeout, onTimeout: () => false);
    await sub.cancel();
    return success;
  }

  /// Connect via QR code scan or manual IP (Wi-Fi or 4G Cloud Tunnel)
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
      final validTunnel = validateTunnelUrl(tunnel);

      if (hostIsDomain) {
        connectedHost = cleanHost;
        connectedPort = 443;
        ok = await _wifiTransport.connect(cleanHost, 443);
      } else {
        // 1. Try local IP first (fast on local Wi-Fi)
        ok = await _wifiTransport.connect(host, port);

        // 2. If direct LAN failed, try provided tunnel
        if (!ok && validTunnel != null) {
          connectedHost = validTunnel;
          connectedPort = 443;
          ok = await _wifiTransport.connect(validTunnel, 443);
        }

        // 3. Fallback: Query live cloud presence for updated tunnel URL
        if (!ok && serverName != null && serverName.isNotEmpty) {
          final presence = await _queryPresence(serverName, pin);
          if (presence != null) {
            final freshTunnel = validateTunnelUrl(presence['tunnel']);
            if (freshTunnel != null && freshTunnel != validTunnel) {
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
        tunnel: validTunnel ?? tunnel,
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

      // Wait for server to verify PIN and send PAIR_RESPONSE
      final okAuth = await _waitForAuthentication(timeout: const Duration(seconds: 15));
      if (!okAuth && _lastError == null) {
        _lastError = 'Pairing timed out. Verify PIN and network connection.';
        notifyListeners();
      }
      return okAuth;
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

      if (targetDevice != null && !targetDevice.autoConnectEnabled) {
        final reEnabled = targetDevice.copyWith(autoConnectEnabled: true);
        _saveOrUpdatePairedDevice(reEnabled);
      }

      _activeDevice = device;
      _status = ConnectionStatus.connecting;
      notifyListeners();

      // Priority 1: Try direct local connection first (instant if on same Wi-Fi)
      bool ok = await _wifiTransport.connect(device.ip, device.port);
      if (ok) {
        if (device.authToken.isNotEmpty) {
          _wifiTransport.send(KeyLinkMessage.authRequest(deviceId: _deviceId, authToken: device.authToken));
          final authOk = await _waitForAuthentication(timeout: const Duration(seconds: 5));
          if (authOk) return true;
        } else {
          return true;
        }
      }

      // Priority 2: Query latest live endpoint from presence rendezvous (picks newest timestamp)
      PairedDevice currentDevice = device;
      final presence = await _queryPresence(device.name, device.pin);
      if (presence != null) {
        final newIp = presence['ip']?.toString();
        final newPort = int.tryParse(presence['port']?.toString() ?? '') ?? 58921;
        final validTunnel = validateTunnelUrl(presence['tunnel']);

        currentDevice = currentDevice.copyWith(
          ip: (newIp != null && newIp.isNotEmpty) ? newIp : currentDevice.ip,
          port: newPort,
          tunnel: validTunnel ?? currentDevice.tunnel,
        );
        _saveOrUpdatePairedDevice(currentDevice);
        _activeDevice = currentDevice;

        // If on same Wi-Fi with new IP:
        if (newIp != null && newIp.isNotEmpty && newIp != device.ip) {
          ok = await _wifiTransport.connect(newIp, newPort);
          if (ok) {
            if (currentDevice.authToken.isNotEmpty) {
              _wifiTransport.send(KeyLinkMessage.authRequest(deviceId: _deviceId, authToken: currentDevice.authToken));
              final authOk = await _waitForAuthentication(timeout: const Duration(seconds: 5));
              if (authOk) return true;
            } else {
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
            final authOk = await _waitForAuthentication(timeout: const Duration(seconds: 15));
            if (authOk) return true;
          }
          // Autonomous fallback to PIN pairing if token is invalid or server restarted
          final devicePin = currentDevice.pin;
          if (devicePin != null && devicePin.isNotEmpty) {
            _wifiTransport.send(KeyLinkMessage.pairRequest(
              deviceId: _deviceId,
              deviceName: _deviceName,
              pin: devicePin,
              os: 'android',
            ));
            final pairOk = await _waitForAuthentication(timeout: const Duration(seconds: 15));
            if (pairOk) return true;
          } else if (currentDevice.authToken.isEmpty) {
            return true;
          }
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
  }

  /// Connect via Bluetooth when Wi-Fi is unavailable
  Future<bool> connectViaBluetooth(BluetoothDeviceItem device) async {
    _lastError = null;
    _connectionMode = ConnectionMode.bluetooth;
    _activeDevice = PairedDevice(
      id: device.id,
      name: device.name,
      ip: device.address,
      port: 0,
      authToken: 'bt_authorized_token',
    );

    final ok = await _bluetoothTransport.connectBluetoothDevice(device);
    if (!ok) {
      _lastError = 'Bluetooth connection failed to ${device.name}';
      notifyListeners();
      return false;
    }

    _status = ConnectionStatus.connected;
    notifyListeners();
    return true;
  }

  /// Called when the app enters background or user switches apps
  void onAppBackgrounded() {
    // Keep connection active in background, but pause heavy video stream to save cellular data & battery
    if (isConnected && _connectionMode == ConnectionMode.qrWifi) {
      _wifiTransport.send(KeyLinkMessage.screenStreamStop());
    }
  }

  /// Called when the app returns from background or app switch
  void onAppResumed() {
    if (_activeDevice != null && _activeDevice!.autoConnectEnabled) {
      _acquireNativeLocks();
      if (_status != ConnectionStatus.connected) {
        if (_connectionMode == ConnectionMode.qrWifi) {
          autoConnect(targetDevice: _activeDevice);
        } else {
          _bluetoothTransport.connect(_activeDevice!.name, 0);
        }
      } else {
        final ok = _activeTransport.send(KeyLinkMessage.ping(DateTime.now().millisecondsSinceEpoch));
        if (!ok && _connectionMode == ConnectionMode.qrWifi) {
          autoConnect(targetDevice: _activeDevice);
        }
      }
    }
  }

  Future<void> disconnect({String reason = 'user_logout', bool explicitUserDisconnect = false}) async {
    stopAudioStream();
    await _releaseNativeLocks();
    if (explicitUserDisconnect && _activeDevice != null) {
      final updated = _activeDevice!.copyWith(autoConnectEnabled: false);
      _saveOrUpdatePairedDevice(updated);
      _activeDevice = updated;
    }
    await _wifiTransport.disconnect(reason: reason);
    await _bluetoothTransport.disconnect(reason: reason);
    _status = ConnectionStatus.disconnected;
    notifyListeners();
  }

  Future<void> removeDevice(PairedDevice device) async {
    if (isConnected) {
      _activeTransport.send(KeyLinkMessage.removeDevice(
        deviceId: _deviceId,
        targetDeviceId: device.id,
      ));
      await Future.delayed(const Duration(milliseconds: 200));
    }
    _pairedDevices.removeWhere((d) => d.id == device.id || (d.ip == device.ip && d.port == device.port));
    if (_activeDevice?.id == device.id || (_activeDevice?.ip == device.ip && _activeDevice?.port == device.port)) {
      _activeDevice = null;
      await disconnect(reason: 'device_removed');
    }
    await _savePairedDevices();
    notifyListeners();
  }

  Future<void> emergencyDisconnect() async {
    stopAudioStream();
    HapticFeedback.heavyImpact();
    await _releaseNativeLocks();
    await _wifiTransport.disconnect(reason: 'emergency');
    await _bluetoothTransport.disconnect(reason: 'emergency');
    _status = ConnectionStatus.disconnected;
    _lastError = 'Emergency Disconnect Triggered';
    notifyListeners();
  }

  void _saveOrUpdatePairedDevice(PairedDevice device) {
    final idx = _pairedDevices.indexWhere((d) => d.ip == device.ip && d.port == device.port);
    if (idx >= 0) {
      _pairedDevices[idx] = device;
    } else {
      _pairedDevices.add(device);
    }
    _savePairedDevices();
    notifyListeners();
  }

  Future<void> forgetDevice(String id) async {
    _pairedDevices.removeWhere((d) => d.id == id);
    if (_activeDevice?.id == id) {
      await disconnect(reason: 'device_removed');
      _activeDevice = null;
    }
    await _savePairedDevices();
    notifyListeners();
  }

  // --- Input Command Senders (Unified over Wi-Fi and Bluetooth) ---

  void sendMouseMove(double dx, double dy) {
    if (!isConnected) return;
    _activeTransport.send(KeyLinkMessage.mouseMove(dx: dx, dy: dy));
  }

  void sendMouseClick(String button, String action) {
    if (!isConnected) return;
    _activeTransport.send(KeyLinkMessage.mouseClick(button: button, action: action));
  }

  void sendMouseScroll(double dx, double dy) {
    if (!isConnected) return;
    _activeTransport.send(KeyLinkMessage.mouseScroll(dx: dx, dy: dy));
  }

  void sendTextInput(String text) {
    if (!isConnected || text.isEmpty) return;
    _activeTransport.send(KeyLinkMessage.textInput(text));
  }

  void sendKeyEvent(String key, {String action = 'press', List<String> modifiers = const []}) {
    if (!isConnected) return;
    _activeTransport.send(KeyLinkMessage.keyEvent(key: key, action: action, modifiers: modifiers));
  }

  void sendShortcut(String action) {
    if (!isConnected) return;
    _activeTransport.send(KeyLinkMessage.shortcut(action));
  }

  void sendVoiceCommand(String text, {String? lang}) {
    if (!isConnected || text.trim().isEmpty) return;
    _activeTransport.send(KeyLinkMessage.voiceCommand(text.trim(), lang: lang));
  }

  void startScreenStream({int quality = 65, int maxWidth = 1280, int fps = 20}) {
    if (!isConnected) return;
    _activeTransport.send(KeyLinkMessage.screenStreamStart(quality: quality, maxWidth: maxWidth, fps: fps));
  }

  void stopScreenStream() {
    if (!isConnected) return;
    _activeTransport.send(KeyLinkMessage.screenStreamStop());
  }

  void sendFrameAck() {
    if (!isConnected) return;
    _activeTransport.send(KeyLinkMessage.frameAck());
  }

  void sendTouchEvent(String action, double x, double y) {
    if (!isConnected) return;
    _activeTransport.send(KeyLinkMessage.touchEvent(action: action, x: x, y: y));
  }

  void startAudioStream({bool userInitiated = false}) {
    if (!isConnected) return;
    if (userInitiated) {
      _userMutedAudio = false;
    }
    _isAudioStreaming = true;
    if (Platform.isAndroid) {
      _bgChannel.invokeMethod('setAudioMuted', {'isMuted': false});
    }
    _wifiTransport.send(KeyLinkMessage.audioStreamStart());
    notifyListeners();
  }

  void stopAudioStream({bool userInitiated = false}) {
    if (userInitiated) {
      _userMutedAudio = true;
    }
    _isAudioStreaming = false;
    if (Platform.isAndroid) {
      _bgChannel.invokeMethod('stopAudio');
      _bgChannel.invokeMethod('setAudioMuted', {'isMuted': true});
    }
    if (isConnected) {
      _wifiTransport.send(KeyLinkMessage.audioStreamStop());
    }
    notifyListeners();
  }

  void toggleAudioStream() {
    if (_isAudioStreaming) {
      stopAudioStream(userInitiated: true);
    } else {
      startAudioStream(userInitiated: true);
    }
  }

  void startMic() {
    if (!isConnected) return;
    _isMicActive = true;
    if (Platform.isAndroid) {
      _bgChannel.invokeMethod('startMicRecording', {
        'sampleRate': 16000,
      });
    }
    _wifiTransport.send(KeyLinkMessage.micStreamStart());
    notifyListeners();
  }

  void stopMic() {
    _isMicActive = false;
    if (Platform.isAndroid) {
      _bgChannel.invokeMethod('stopMicRecording');
    }
    if (isConnected) {
      _wifiTransport.send(KeyLinkMessage.micStreamStop());
    }
    notifyListeners();
  }

  void toggleMic() {
    if (_isMicActive) {
      stopMic();
    } else {
      startMic();
    }
  }

  @override
  void dispose() {
    stopMic();
    stopAudioStream();
    _audioStreamSub?.cancel();
    _autoConnectTimer?.cancel();
    _latencyPollTimer?.cancel();
    _wifiStatusSub?.cancel();
    _wifiMessageSub?.cancel();
    _bluetoothStatusSub?.cancel();
    _bluetoothMessageSub?.cancel();
    _wifiTransport.dispose();
    _bluetoothTransport.dispose();
    _voiceResponseController.close();
    super.dispose();
  }
}
