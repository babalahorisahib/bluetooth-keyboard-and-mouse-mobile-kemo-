import 'dart:convert';

/// Represents all valid message types in the KeyLink protocol v1.
enum MessageType {
  pairRequest,
  pairResponse,
  authRequest,
  authResponse,
  mouseMove,
  mouseClick,
  mouseScroll,
  textInput,
  keyEvent,
  shortcut,
  ping,
  pong,
  voiceCommand,
  voiceResponse,
  screenStreamStart,
  screenStreamStop,
  audioStreamStart,
  audioStreamStop,
  micStreamStart,
  micStreamStop,
  touchEvent,
  frameAck,
  disconnect,
  removeDevice,
  deviceRemoved,
  serverDisconnect,
  statusUpdate,
  unknown;

  static MessageType fromString(String str) {
    switch (str) {
      case 'PAIR_REQUEST':
        return MessageType.pairRequest;
      case 'PAIR_RESPONSE':
        return MessageType.pairResponse;
      case 'AUTH_REQUEST':
        return MessageType.authRequest;
      case 'AUTH_RESPONSE':
        return MessageType.authResponse;
      case 'MOUSE_MOVE':
        return MessageType.mouseMove;
      case 'MOUSE_CLICK':
        return MessageType.mouseClick;
      case 'MOUSE_SCROLL':
        return MessageType.mouseScroll;
      case 'TEXT_INPUT':
        return MessageType.textInput;
      case 'KEY_EVENT':
        return MessageType.keyEvent;
      case 'SHORTCUT':
        return MessageType.shortcut;
      case 'PING':
        return MessageType.ping;
      case 'PONG':
        return MessageType.pong;
      case 'VOICE_COMMAND':
        return MessageType.voiceCommand;
      case 'VOICE_RESPONSE':
        return MessageType.voiceResponse;
      case 'SCREEN_STREAM_START':
        return MessageType.screenStreamStart;
      case 'SCREEN_STREAM_STOP':
        return MessageType.screenStreamStop;
      case 'AUDIO_STREAM_START':
        return MessageType.audioStreamStart;
      case 'AUDIO_STREAM_STOP':
        return MessageType.audioStreamStop;
      case 'MIC_STREAM_START':
        return MessageType.micStreamStart;
      case 'MIC_STREAM_STOP':
        return MessageType.micStreamStop;
      case 'TOUCH_EVENT':
        return MessageType.touchEvent;
      case 'FRAME_ACK':
        return MessageType.frameAck;
      case 'DISCONNECT':
        return MessageType.disconnect;
      case 'REMOVE_DEVICE':
        return MessageType.removeDevice;
      case 'DEVICE_REMOVED':
        return MessageType.deviceRemoved;
      case 'SERVER_DISCONNECT':
        return MessageType.serverDisconnect;
      case 'STATUS_UPDATE':
        return MessageType.statusUpdate;
      default:
        return MessageType.unknown;
    }
  }

  String toWireString() {
    switch (this) {
      case MessageType.pairRequest:
        return 'PAIR_REQUEST';
      case MessageType.pairResponse:
        return 'PAIR_RESPONSE';
      case MessageType.authRequest:
        return 'AUTH_REQUEST';
      case MessageType.authResponse:
        return 'AUTH_RESPONSE';
      case MessageType.mouseMove:
        return 'MOUSE_MOVE';
      case MessageType.mouseClick:
        return 'MOUSE_CLICK';
      case MessageType.mouseScroll:
        return 'MOUSE_SCROLL';
      case MessageType.textInput:
        return 'TEXT_INPUT';
      case MessageType.keyEvent:
        return 'KEY_EVENT';
      case MessageType.shortcut:
        return 'SHORTCUT';
      case MessageType.ping:
        return 'PING';
      case MessageType.pong:
        return 'PONG';
      case MessageType.voiceCommand:
        return 'VOICE_COMMAND';
      case MessageType.voiceResponse:
        return 'VOICE_RESPONSE';
      case MessageType.screenStreamStart:
        return 'SCREEN_STREAM_START';
      case MessageType.screenStreamStop:
        return 'SCREEN_STREAM_STOP';
      case MessageType.audioStreamStart:
        return 'AUDIO_STREAM_START';
      case MessageType.audioStreamStop:
        return 'AUDIO_STREAM_STOP';
      case MessageType.micStreamStart:
        return 'MIC_STREAM_START';
      case MessageType.micStreamStop:
        return 'MIC_STREAM_STOP';
      case MessageType.touchEvent:
        return 'TOUCH_EVENT';
      case MessageType.frameAck:
        return 'FRAME_ACK';
      case MessageType.disconnect:
        return 'DISCONNECT';
      case MessageType.removeDevice:
        return 'REMOVE_DEVICE';
      case MessageType.deviceRemoved:
        return 'DEVICE_REMOVED';
      case MessageType.serverDisconnect:
        return 'SERVER_DISCONNECT';
      case MessageType.statusUpdate:
        return 'STATUS_UPDATE';
      case MessageType.unknown:
        return 'UNKNOWN';
    }
  }
}

/// Transport-agnostic envelope for KeyLink communication
class KeyLinkMessage {
  final int version;
  final MessageType type;
  final String? id;
  final Map<String, dynamic> payload;

  const KeyLinkMessage({
    this.version = 1,
    required this.type,
    this.id,
    required this.payload,
  });

  factory KeyLinkMessage.fromJson(Map<String, dynamic> json) {
    return KeyLinkMessage(
      version: json['v'] as int? ?? 1,
      type: MessageType.fromString(json['type'] as String? ?? ''),
      id: json['id'] as String?,
      payload: (json['payload'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'v': version,
      'type': type.toWireString(),
      'payload': payload,
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  String serialize() => jsonEncode(toJson());

  static KeyLinkMessage? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return KeyLinkMessage.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  // Factory builders for standard messages
  static KeyLinkMessage pairRequest({
    required String deviceId,
    required String deviceName,
    required String os,
    required String pin,
  }) {
    return KeyLinkMessage(
      type: MessageType.pairRequest,
      payload: {
        'device_id': deviceId,
        'device_name': deviceName,
        'os': os,
        'pin': pin,
      },
    );
  }

  static KeyLinkMessage authRequest({
    required String deviceId,
    required String authToken,
  }) {
    return KeyLinkMessage(
      type: MessageType.authRequest,
      payload: {
        'device_id': deviceId,
        'auth_token': authToken,
      },
    );
  }

  static KeyLinkMessage mouseMove({
    required double dx,
    required double dy,
  }) {
    return KeyLinkMessage(
      type: MessageType.mouseMove,
      payload: {
        'dx': dx,
        'dy': dy,
      },
    );
  }

  static KeyLinkMessage mouseClick({
    required String button,
    required String action,
  }) {
    return KeyLinkMessage(
      type: MessageType.mouseClick,
      payload: {
        'button': button, // left, right, middle
        'action': action, // click, double, down, up
      },
    );
  }

  static KeyLinkMessage mouseScroll({
    required double dx,
    required double dy,
  }) {
    return KeyLinkMessage(
      type: MessageType.mouseScroll,
      payload: {
        'dx': dx,
        'dy': dy,
      },
    );
  }

  static KeyLinkMessage textInput(String text) {
    return KeyLinkMessage(
      type: MessageType.textInput,
      payload: {
        'text': text,
      },
    );
  }

  static KeyLinkMessage keyEvent({
    required String key,
    String action = 'press',
    List<String> modifiers = const [],
  }) {
    return KeyLinkMessage(
      type: MessageType.keyEvent,
      payload: {
        'key': key,
        'action': action,
        'modifiers': modifiers,
      },
    );
  }

  static KeyLinkMessage shortcut(String action) {
    return KeyLinkMessage(
      type: MessageType.shortcut,
      payload: {
        'action': action,
      },
    );
  }

  static KeyLinkMessage voiceCommand(String text, {String? lang}) {
    return KeyLinkMessage(
      type: MessageType.voiceCommand,
      payload: {
        'text': text,
        if (lang != null) 'lang': lang,
      },
    );
  }

  static KeyLinkMessage screenStreamStart({int quality = 65, int maxWidth = 1280, int fps = 20}) {
    return KeyLinkMessage(
      type: MessageType.screenStreamStart,
      payload: {
        'quality': quality,
        'max_width': maxWidth,
        'fps': fps,
      },
    );
  }

  static KeyLinkMessage screenStreamStop() {
    return const KeyLinkMessage(
      type: MessageType.screenStreamStop,
      payload: {},
    );
  }

  static KeyLinkMessage audioStreamStart() {
    return const KeyLinkMessage(
      type: MessageType.audioStreamStart,
      payload: {},
    );
  }

  static KeyLinkMessage audioStreamStop() {
    return const KeyLinkMessage(
      type: MessageType.audioStreamStop,
      payload: {},
    );
  }

  static KeyLinkMessage micStreamStart() {
    return const KeyLinkMessage(
      type: MessageType.micStreamStart,
      payload: {},
    );
  }

  static KeyLinkMessage micStreamStop() {
    return const KeyLinkMessage(
      type: MessageType.micStreamStop,
      payload: {},
    );
  }

  static KeyLinkMessage touchEvent({
    required String action,
    required double x,
    required double y,
  }) {
    return KeyLinkMessage(
      type: MessageType.touchEvent,
      payload: {
        'action': action,
        'x': x,
        'y': y,
      },
    );
  }

  static KeyLinkMessage frameAck() {
    return const KeyLinkMessage(
      type: MessageType.frameAck,
      payload: {},
    );
  }

  static KeyLinkMessage ping(int clientTimestamp) {
    return KeyLinkMessage(
      type: MessageType.ping,
      payload: {
        'timestamp': clientTimestamp,
      },
    );
  }

  static KeyLinkMessage disconnect(String reason) {
    return KeyLinkMessage(
      type: MessageType.disconnect,
      payload: {
        'reason': reason,
      },
    );
  }

  static KeyLinkMessage removeDevice({
    required String deviceId,
    String? targetDeviceId,
  }) {
    return KeyLinkMessage(
      type: MessageType.removeDevice,
      payload: {
        'device_id': deviceId,
        if (targetDeviceId != null) 'target_device_id': targetDeviceId,
      },
    );
  }
}
