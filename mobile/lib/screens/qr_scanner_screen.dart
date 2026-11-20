import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/connection_service.dart';

class QrScannerScreen extends StatefulWidget {
  final ConnectionService connectionService;

  const QrScannerScreen({super.key, required this.connectionService});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _isProcessing = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final raw = barcode.rawValue!;
    try {
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic> &&
          data.containsKey('ip') &&
          data.containsKey('port') &&
          data.containsKey('pin')) {
        _isProcessing = true;
        if (mounted) setState(() {});

        final host = data['ip'] as String;
        final port = data['port'] as int;
        final pin = data['pin'].toString();
        final name = data['name'] as String? ?? 'KeyLink PC';
        final tunnel = data['tunnel'] as String?;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tunnel != null && tunnel.isNotEmpty
                ? 'Connecting to $name (Auto 4G / Wi-Fi)...'
                : 'Connecting to $name ($host:$port)...'),
            duration: const Duration(seconds: 12),
          ),
        );

        final ok = await widget.connectionService.pairWithServer(
          host: host,
          port: port,
          pin: pin,
          serverName: name,
          tunnel: tunnel,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          if (ok) {
            Navigator.of(context).pop(true);
          } else {
            setState(() => _isProcessing = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(widget.connectionService.lastError ?? 'Failed to connect. Check Wi-Fi or 4G connection.'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      }
    } catch (_) {
      // Not a valid KeyLink QR code, continue scanning
    }
  }

  void _showManualConnectionDialog() {
    final ipController = TextEditingController(text: '192.168.1.109');
    final portController = TextEditingController(text: '58921');
    final pinController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cable_rounded, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('Manual PC Connection'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ipController,
                decoration: const InputDecoration(
                  labelText: 'Computer IP or 4G Relay URL',
                  hintText: '192.168.1.109 or xxx.trycloudflare.com',
                  prefixIcon: Icon(Icons.language_rounded),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  '💡 At home use Wi-Fi IP (192.168.x.x). Outside use 4G Relay URL shown on PC.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              TextField(
                controller: pinController,
                decoration: const InputDecoration(
                  labelText: 'Security PIN (from PC screen)',
                  hintText: 'e.g. 179887',
                  prefixIcon: Icon(Icons.pin_rounded),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: portController,
                decoration: const InputDecoration(
                  labelText: 'Port (default 58921 / 443)',
                  hintText: '58921',
                  prefixIcon: Icon(Icons.tag_rounded),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              String raw = ipController.text.trim();
              raw = raw.replaceFirst(RegExp(r'^(https?|wss?)://'), '');
              raw = raw.replaceAll(RegExp(r'/+$'), '');

              final pin = pinController.text.trim();
              if (raw.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter Computer IP or 4G Relay URL')),
                );
                return;
              }
              if (pin.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter 6-digit Security PIN shown on PC')),
                );
                return;
              }

              final bool isDomain = raw.contains('.') && RegExp(r'[a-zA-Z]').hasMatch(raw);
              final port = int.tryParse(portController.text.trim()) ?? (isDomain ? 443 : 58921);

              Navigator.pop(ctx);
              setState(() => _isProcessing = true);

              final ok = await widget.connectionService.pairWithServer(
                host: raw,
                port: port,
                pin: pin,
                serverName: 'WASEEM',
                tunnel: isDomain ? raw : null,
              );

              if (mounted) {
                if (ok) {
                  Navigator.of(context).pop(true);
                } else {
                  setState(() => _isProcessing = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(widget.connectionService.lastError ?? 'Connection failed. Check PIN & network.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  void _fastConnectDirect() async {
    if (_isProcessing) return;
    final saved = widget.connectionService.pairedDevices;
    if (saved.isNotEmpty) {
      setState(() => _isProcessing = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connecting to ${saved.first.name}...'),
          duration: const Duration(seconds: 3),
        ),
      );
      final ok = await widget.connectionService.connectToPairedDevice(saved.first);
      if (mounted) {
        if (ok) {
          Navigator.of(context).pop(true);
        } else {
          setState(() => _isProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.connectionService.lastError ?? 'Could not reach PC. Make sure MobileKemo is open on PC or point camera at QR code!'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Point camera at the QR code on your PC screen to connect!'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Desktop QR Code'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_rounded, color: Colors.amberAccent),
            tooltip: '1-Tap Fast Connect',
            onPressed: _fastConnectDirect,
          ),
          IconButton(
            icon: const Icon(Icons.edit_note_rounded),
            tooltip: 'Enter IP Manually',
            onPressed: _showManualConnectionDialog,
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              return Container(
                color: const Color(0xFF0F172A),
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_off_rounded, color: Colors.amber, size: 56),
                      const SizedBox(height: 16),
                      const Text(
                        'Camera is in use by another app (e.g. Zoom)',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Zoom class open hone ki wajah se camera busy hai. Fikar na karein, neechay 1-Tap button dabayein!',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.flash_on_rounded, color: Colors.amberAccent),
                        label: const Text('⚡ 1-Tap Connect to PC', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        onPressed: _fastConnectDirect,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          // Top Wi-Fi Status Card
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xEE0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF3B82F6), width: 1.5),
              ),
              child: const Row(
                children: [
                  Icon(Icons.qr_code_scanner_rounded, color: Colors.lightBlueAccent, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Point camera at QR Code on PC screen (Works on Wi-Fi & 4G!)',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Viewfinder overlay
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blueAccent, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Column(
              children: [
                // 1-Tap Fast Connect Shortcut Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.flash_on_rounded, color: Colors.amberAccent),
                    label: const Text(
                      '⚡ 1-Tap Connect (Bypass Camera)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isProcessing ? null : _fastConnectDirect,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.keyboard_outlined, color: Colors.white),
                  label: const Text('Enter IP & PIN Manually', style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.black54,
                    side: const BorderSide(color: Colors.white38),
                  ),
                  onPressed: _showManualConnectionDialog,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
