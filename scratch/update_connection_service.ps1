$content = [System.IO.File]::ReadAllText("mobile\lib\services\connection_service.dart")

$oldImport = @'
import 'dart:io';
import 'package:flutter/foundation.dart';
'@

$newImport = @'
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
'@

$content = $content.Replace($oldImport, $newImport)

$oldActiveDev = @'
    _activeDevice = PairedDevice(
      id: const Uuid().v4(),
      name: serverName ?? 'KeyLink PC',
      ip: connectedHost,
      port: connectedPort,
      tunnel: tunnel,
      authToken: '',
    );
'@

$newActiveDev = @'
    _activeDevice = PairedDevice(
      id: const Uuid().v4(),
      name: serverName ?? 'KeyLink PC',
      ip: connectedHost,
      port: connectedPort,
      tunnel: tunnel,
      authToken: '',
      pin: pin,
    );
'@

$content = $content.Replace($oldActiveDev, $newActiveDev)

$oldTopicLogic = @'
    // Priority 2: If on different network or IP changed, query live presence from ntfy.sh rendezvous
    final sanitizedName = device.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final topic = 'kemo_sync_$sanitizedName';
    PairedDevice currentDevice = device;
'@

$newTopicLogic = @'
    // Priority 2: If on different network or IP changed, query live presence from secure ntfy.sh rendezvous
    final sanitizedName = device.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final topicsToTry = <String>[];
    if (device.pin != null && device.pin!.isNotEmpty) {
      final hash = sha256.convert(utf8.encode('kemo_rendezvous:$sanitizedName:${device.pin}')).toString();
      topicsToTry.add('kemo_v2_${hash.substring(0, 20)}');
    }
    topicsToTry.add('kemo_sync_$sanitizedName');

    PairedDevice currentDevice = device;
'@

$content = $content.Replace($oldTopicLogic, $newTopicLogic)

$oldPollLogic = @'
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final res = await client.getUrl(Uri.parse('https://ntfy.sh/$topic/json?poll=1')).timeout(const Duration(seconds: 2));
      final resp = await res.close();
'@

$newPollLogic = @'
    for (final topic in topicsToTry) {
      if (ok) break;
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
        final res = await client.getUrl(Uri.parse('https://ntfy.sh/$topic/json?poll=1')).timeout(const Duration(seconds: 2));
        final resp = await res.close();
'@

$content = $content.Replace($oldPollLogic, $newPollLogic)

$oldEndPoll = @'
      client.close();
    } catch (_) {}
'@

$newEndPoll = @'
        client.close();
      } catch (_) {}
    }
'@

$content = $content.Replace($oldEndPoll, $newEndPoll)

[System.IO.File]::WriteAllText("mobile\lib\services\connection_service.dart", $content)
Write-Output "Updated connection_service.dart successfully"
