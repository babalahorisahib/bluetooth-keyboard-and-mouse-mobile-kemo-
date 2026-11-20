import 'dart:async';
import '../models/protocol_message.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  pairingRequired,
  authenticating,
  connected,
  error,
}

/// Abstract transport layer interface.
/// Keeps network/Wi-Fi and Bluetooth decoupled from input generation.
abstract class KeyLinkTransport {
  /// Stream of connection status changes
  Stream<ConnectionStatus> get statusStream;

  /// Current connection status
  ConnectionStatus get status;

  /// Stream of incoming protocol messages from the host
  Stream<KeyLinkMessage> get messageStream;

  /// Round-trip ping latency in milliseconds
  int get latencyMs;

  /// Connect to the desktop agent
  Future<bool> connect(String host, int port);

  /// Disconnect the active transport
  Future<void> disconnect({String reason = 'user_logout'});

  /// Send a protocol message to the desktop agent
  bool send(KeyLinkMessage message);

  /// Release resources
  void dispose();
}
