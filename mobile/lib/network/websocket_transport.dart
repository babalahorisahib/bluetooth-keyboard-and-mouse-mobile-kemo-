import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status_codes;
import '../models/protocol_message.dart';
import 'transport_interface.dart';

class AudioPacket {
  final int channels;
  final int sampleRate;
  final int sequence;
  final Uint8List pcmData;

  const AudioPacket({
    required this.channels,
    required this.sampleRate,
    required this.sequence,
    required this.pcmData,
  });
}

class WebSocketTransport implements KeyLinkTransport {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  ConnectionStatus _status = ConnectionStatus.disconnected;
  final StreamController<ConnectionStatus> _statusController =
      StreamController<ConnectionStatus>.broadcast();

  final StreamController<KeyLinkMessage> _messageController =
      StreamController<KeyLinkMessage>.broadcast();

  final StreamController<Uint8List> _screenFrameController =
      StreamController<Uint8List>.broadcast();

  final StreamController<AudioPacket> _audioStreamController =
      StreamController<AudioPacket>.broadcast();

  Stream<Uint8List> get screenStream => _screenFrameController.stream;
  Stream<AudioPacket> get audioStream => _audioStreamController.stream;

  String? _lastHost;
  int? _lastPort;
  String? _connectedHost;
  Future<bool> Function()? onReconnectRequested;
  bool _autoReconnectEnabled = true;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 500;

  int _latencyMs = 0;

  String? get connectedHost => _connectedHost;

  @override
  ConnectionStatus get status => _status;

  @override
  Stream<ConnectionStatus> get statusStream => _statusController.stream;

  @override
  Stream<KeyLinkMessage> get messageStream => _messageController.stream;

  @override
  int get latencyMs => _latencyMs;

  void _updateStatus(ConnectionStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _statusController.add(_status);
    }
  }

  @override
  Future<bool> connect(String host, int port) async {
    _lastHost = host;
    _lastPort = port;
    _autoReconnectEnabled = false;

    _stopHeartbeat();
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    _updateStatus(ConnectionStatus.connecting);

    try {
      String cleanHost = host.trim();
      cleanHost = cleanHost.replaceFirst(RegExp(r'^(https?|wss?)://'), '');
      cleanHost = cleanHost.replaceAll(RegExp(r'/+$'), '');

      final bool isDomainOrTunnel = cleanHost.contains('.trycloudflare.com') ||
          cleanHost.contains('.ngrok') ||
          cleanHost.contains('.pinggy') ||
          cleanHost.contains('.localhost.run') ||
          cleanHost.contains('.loca.lt') ||
          port == 443 ||
          (!cleanHost.contains(':') && RegExp(r'[a-zA-Z]').hasMatch(cleanHost));

      if (isDomainOrTunnel) {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 25)
          ..badCertificateCallback = ((X509Certificate cert, String host, int port) => true);
        final ws = await WebSocket.connect(
          'wss://$cleanHost',
          customClient: client,
        ).timeout(const Duration(seconds: 25));
        _channel = IOWebSocketChannel(ws);
      } else {
        final rawUrl = cleanHost.contains(':') ? 'ws://$cleanHost' : 'ws://$cleanHost:$port';
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 3);
        final ws = await WebSocket.connect(
          rawUrl,
          customClient: client,
        ).timeout(const Duration(seconds: 3));
        _channel = IOWebSocketChannel(ws);
      }

      _subscription = _channel!.stream.listen(
        _onMessageReceived,
        onError: _onError,
        onDone: _onDone,
      );

      _connectedHost = cleanHost;
      _updateStatus(ConnectionStatus.authenticating);
      _startHeartbeat();
      _reconnectAttempts = 0;
      return true;
    } catch (e) {
      _stopHeartbeat();
      _updateStatus(ConnectionStatus.disconnected);
      return false;
    }
  }

  void markAuthenticated() {
    _autoReconnectEnabled = true;
    _reconnectAttempts = 0;
    _updateStatus(ConnectionStatus.connected);
  }

  void _onMessageReceived(dynamic data) {
    if (data is String) {
      final msg = KeyLinkMessage.tryParse(data);
      if (msg != null) {
        if (msg.type == MessageType.pong) {
          final clientTs = msg.payload['client_timestamp'] as int? ?? 0;
          if (clientTs > 0) {
            _latencyMs = DateTime.now().millisecondsSinceEpoch - clientTs;
          }
        }
        _messageController.add(msg);
      }
    } else {
      Uint8List? bytes;
      if (data is Uint8List) {
        bytes = data;
      } else if (data is List<int>) {
        bytes = Uint8List.fromList(data);
      } else if (data is ByteBuffer) {
        bytes = data.asUint8List();
      } else if (data is ByteData) {
        bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } else if (data is TypedData) {
        bytes = Uint8List.view(data.buffer);
      }
      if (bytes != null && bytes.isNotEmpty) {
        if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
          // JPEG Screen Frame
          _screenFrameController.add(bytes);
        } else if (bytes.length >= 12 &&
            bytes[0] == 0x4B &&
            bytes[1] == 0x41 &&
            bytes[2] == 0x55 &&
            bytes[3] == 0x44) {
          // 'KAUD' Audio Packet
          final channels = bytes[5];
          final byteData = ByteData.sublistView(bytes);
          final sampleRate = byteData.getUint32(6, Endian.little);
          final seq = byteData.getUint16(10, Endian.little);
          final pcm = bytes.sublist(12);

          _audioStreamController.add(AudioPacket(
            channels: channels,
            sampleRate: sampleRate,
            sequence: seq,
            pcmData: pcm,
          ));
        }
      }
    }
  }

  void _onError(dynamic error) {
    _stopHeartbeat();
    _updateStatus(ConnectionStatus.error);
    _scheduleReconnect();
  }

  void _onDone() {
    _stopHeartbeat();
    if (_status != ConnectionStatus.disconnected) {
      _updateStatus(ConnectionStatus.disconnected);
      _scheduleReconnect();
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_status == ConnectionStatus.connected) {
        final ok = send(KeyLinkMessage.ping(DateTime.now().millisecondsSinceEpoch));
        if (!ok && _autoReconnectEnabled) {
          _onError('Heartbeat failed');
        }
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _scheduleReconnect() {
    if (!_autoReconnectEnabled) {
      return;
    }
    if (_reconnectAttempts >= maxReconnectAttempts) {
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    final delaySeconds = (_reconnectAttempts).clamp(1, 3);
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (_status != ConnectionStatus.connected && _autoReconnectEnabled) {
        if (onReconnectRequested != null) {
          final ok = await onReconnectRequested!();
          if (ok) return;
        }
        if (_lastHost != null && _lastPort != null) {
          connect(_lastHost!, _lastPort!);
        }
      }
    });
  }

  void triggerImmediateReconnect() {
    _autoReconnectEnabled = true;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    if (onReconnectRequested != null) {
      onReconnectRequested!();
    } else if (_lastHost != null && _lastPort != null) {
      connect(_lastHost!, _lastPort!);
    }
  }

  int _micSeq = 0;

  bool sendMicChunk(Uint8List pcmData, {int sampleRate = 16000, int channels = 1}) {
    if (_channel == null || _status == ConnectionStatus.disconnected) {
      return false;
    }
    try {
      final packet = Uint8List(12 + pcmData.length);
      final byteData = ByteData.sublistView(packet);
      // 'KMIC' magic header
      packet[0] = 0x4B;
      packet[1] = 0x4D;
      packet[2] = 0x49;
      packet[3] = 0x43;
      packet[4] = 1; // version 1
      packet[5] = channels; // channels (1 for mono)
      byteData.setUint32(6, sampleRate, Endian.little);
      byteData.setUint16(10, _micSeq, Endian.little);
      _micSeq = (_micSeq + 1) & 0xFFFF;
      packet.setRange(12, 12 + pcmData.length, pcmData);
      _channel!.sink.add(packet);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  bool send(KeyLinkMessage message) {
    if (_channel == null || _status == ConnectionStatus.disconnected) {
      return false;
    }
    try {
      _channel!.sink.add(message.serialize());
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> disconnect({String reason = 'user_logout'}) async {
    _autoReconnectEnabled = false;
    _reconnectTimer?.cancel();
    _stopHeartbeat();
    _connectedHost = null;

    if (_channel != null && _status == ConnectionStatus.connected) {
      try {
        send(KeyLinkMessage.disconnect(reason));
        await Future.delayed(const Duration(milliseconds: 50));
      } catch (_) {}
    }

    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close(status_codes.normalClosure);
    _channel = null;

    _updateStatus(ConnectionStatus.disconnected);
  }

  @override
  void dispose() {
    disconnect();
    _statusController.close();
    _messageController.close();
    _screenFrameController.close();
    _audioStreamController.close();
  }
}
