import 'package:flutter_test/flutter_test.dart';
import 'package:keylink_mobile/models/protocol_message.dart';
import 'package:keylink_mobile/models/paired_device.dart';

void main() {
  group('KeyLinkProtocol Tests', () {
    test('Serializes and parses MOUSE_MOVE correctly', () {
      final msg = KeyLinkMessage.mouseMove(dx: 15.5, dy: -3.2);
      final raw = msg.serialize();
      final parsed = KeyLinkMessage.tryParse(raw);

      expect(parsed, isNotNull);
      expect(parsed!.type, MessageType.mouseMove);
      expect(parsed.payload['dx'], 15.5);
      expect(parsed.payload['dy'], -3.2);
    });

    test('Serializes and parses TEXT_INPUT with Urdu and Unicode', () {
      final msg = KeyLinkMessage.textInput('السلام علیکم 123');
      final raw = msg.serialize();
      final parsed = KeyLinkMessage.tryParse(raw);

      expect(parsed, isNotNull);
      expect(parsed!.type, MessageType.textInput);
      expect(parsed.payload['text'], 'السلام علیکم 123');
    });

    test('Serializes and parses PAIR_REQUEST', () {
      final msg = KeyLinkMessage.pairRequest(
        deviceId: 'uuid-1234',
        deviceName: 'Pixel 8',
        os: 'android',
        pin: '654321',
      );
      final raw = msg.serialize();
      final parsed = KeyLinkMessage.tryParse(raw);

      expect(parsed, isNotNull);
      expect(parsed!.type, MessageType.pairRequest);
      expect(parsed.payload['pin'], '654321');
    });

    test('PairedDevice serialization and deserialization', () {
      final device = PairedDevice(
        id: 'dev-1',
        name: 'Work PC',
        ip: '192.168.1.100',
        port: 58921,
        authToken: 'secret_token_123',
        os: 'windows',
      );
      final raw = device.serialize();
      final restored = PairedDevice.deserialize(raw);

      expect(restored, isNotNull);
      expect(restored!.id, 'dev-1');
      expect(restored.name, 'Work PC');
      expect(restored.ip, '192.168.1.100');
      expect(restored.port, 58921);
      expect(restored.authToken, 'secret_token_123');
      expect(restored.os, 'windows');
    });

    test('Serializes and parses VOICE_COMMAND correctly', () {
      final msg = KeyLinkMessage.voiceCommand('Chrome kholo', lang: 'ur');
      final raw = msg.serialize();
      final parsed = KeyLinkMessage.tryParse(raw);

      expect(parsed, isNotNull);
      expect(parsed!.type, MessageType.voiceCommand);
      expect(parsed.payload['text'], 'Chrome kholo');
      expect(parsed.payload['lang'], 'ur');
    });
  });
}
