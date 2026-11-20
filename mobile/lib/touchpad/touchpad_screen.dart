import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../screens/touchscreen_screen.dart';
import '../services/connection_service.dart';
import '../services/settings_service.dart';
import 'expandable_shortcut_sheet.dart';

class TouchpadScreen extends StatefulWidget {
  final ConnectionService connectionService;
  final SettingsService settingsService;
  final bool autoFocusKeyboard;

  const TouchpadScreen({
    super.key,
    required this.connectionService,
    required this.settingsService,
    this.autoFocusKeyboard = true,
  });

  @override
  State<TouchpadScreen> createState() => _TouchpadScreenState();
}

class _TouchpadScreenState extends State<TouchpadScreen> {
  // Pointers tracking for multi-touch
  final Map<int, Offset> _pointerPositions = {};
  int _activePointers = 0;

  // Single-finger tap & double tap detection
  DateTime? _lastTapTime;
  Offset? _lastTapPos;
  bool _isDragging = false;
  Timer? _dragLockTimer;

  // Track movement distance to distinguish tap vs drag
  double _totalDisplacement = 0.0;
  DateTime? _touchStartTime;

  // Live Typing & Phone Keyboard Integration
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  String _previewText = '';
  String _previousText = '';
  bool _showUrduPalette = false;
  bool _isCtrlActive = false;
  bool _isAltActive = false;
  bool _isShiftActive = false;
  bool _isCommandMode = false;
  bool _isLeftButtonHeld = false;
  bool _bottomControlsExpanded = true;

  // Real Mouse Feel: Natural Continuous Velocity Acceleration Curve
  double _accelerateDelta(double delta) {
    final absD = delta.abs();
    if (absD == 0.0) return 0.0;
    // Continuous natural macOS & Windows Precision Touchpad velocity curve:
    // - Micro movements (< 2.5px): 1:1 true sub-pixel precision for selecting text & small controls
    // - Medium glide (2.5px to 12px): smooth progressive ramp from 1.0x to 1.8x
    // - Fast flicks (> 12px): ramps smoothly up to 2.8x for effortless, rapid multi-monitor traversal
    final double ramp = (absD / 12.0).clamp(0.0, 1.8);
    final double multiplier = 1.0 + ramp;
    return delta * multiplier * widget.settingsService.sensitivity;
  }

  // Voice Assistant Integration
  StreamSubscription? _voiceResponseSub;
  String _lastVoiceStatus = '';
  bool _isVoiceSuccess = true;
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechInitialized = false;

  // Urdu layout
  static const List<List<String>> _urduLayout = [
    ['آ', 'ا', 'ب', 'پ', 'ت', 'ٹ', 'ث', 'ج', 'چ', 'ح', 'خ'],
    ['د', 'ڈ', 'ذ', 'ر', 'ڑ', 'ز', 'ژ', 'س', 'ش', 'ص', 'ض'],
    ['ط', 'ظ', 'ع', 'غ', 'ف', 'ق', 'ک', 'گ', 'ل', 'م', 'ن'],
    ['ں', 'و', 'ہ', 'ھ', 'ء', 'ی', 'ے', '؟', '،', '۔'],
  ];

  @override
  void initState() {
    super.initState();

    _inputFocusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.backspace) {
          _performHaptic();
          _sendBackspace();
          return KeyEventResult.handled;
        } else if (event.logicalKey == LogicalKeyboardKey.enter) {
          _performHaptic();
          _sendEnter();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };

    if (widget.autoFocusKeyboard) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _inputFocusNode.requestFocus();
        }
      });
    }

    _voiceResponseSub = widget.connectionService.voiceResponseStream.listen((data) {
      if (!mounted) return;
      final msg = data['message'] as String? ?? '';
      final success = data['success'] as bool? ?? true;
      setState(() {
        _lastVoiceStatus = msg;
        _isVoiceSuccess = success;
      });
      if (widget.settingsService.hapticsEnabled) {
        HapticFeedback.mediumImpact();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  msg,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: success ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    });
  }

  @override
  void dispose() {
    _voiceResponseSub?.cancel();
    _dragLockTimer?.cancel();
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  // --- Touchpad Gestures ---

  void _onPointerDown(PointerDownEvent event) {
    _pointerPositions[event.pointer] = event.position;
    _activePointers = _pointerPositions.length;

    if (_activePointers == 1) {
      _touchStartTime = DateTime.now();
      _totalDisplacement = 0.0;

      // Check if this could be the second tap of a double tap (for drag-and-drop)
      final now = DateTime.now();
      if (_lastTapTime != null &&
          _lastTapPos != null &&
          now.difference(_lastTapTime!).inMilliseconds < 350 &&
          (event.position - _lastTapPos!).distance < 30) {
        _dragLockTimer = Timer(const Duration(milliseconds: 150), () {
          if (mounted && _activePointers == 1) {
            _isDragging = true;
            if (widget.settingsService.hapticsEnabled) {
              HapticFeedback.mediumImpact();
            }
            widget.connectionService.sendMouseClick('left', 'down');
          }
        });
      }
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    final oldPos = _pointerPositions[event.pointer];
    _pointerPositions[event.pointer] = event.position;

    if (oldPos == null) return;
    final delta = event.position - oldPos;
    _totalDisplacement += delta.distance;

    final sensitivity = widget.settingsService.sensitivity;

    if (_activePointers == 1) {
      // 1-finger cursor movement with smooth natural acceleration
      final dx = _accelerateDelta(delta.dx);
      final dy = _accelerateDelta(delta.dy);
      widget.connectionService.sendMouseMove(dx, dy);
    } else if (_activePointers == 2) {
      // 2-finger scrolling
      final invert = widget.settingsService.invertScroll ? -1.0 : 1.0;
      final scrollMultiplier = 3.5 * sensitivity;
      final scrollDx = delta.dx * scrollMultiplier * invert;
      final scrollDy = delta.dy * scrollMultiplier * invert;

      widget.connectionService.sendMouseScroll(scrollDx, scrollDy);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _dragLockTimer?.cancel();
    final wasDragging = _isDragging;
    if (_isDragging) {
      _isDragging = false;
      widget.connectionService.sendMouseClick('left', 'up');
    }

    final now = DateTime.now();
    final duration = _touchStartTime != null
        ? now.difference(_touchStartTime!).inMilliseconds
        : 999;

    // Check tap gestures if minimal displacement
    if (!wasDragging && _totalDisplacement < 15 && duration < 300) {
      if (_activePointers == 1 && widget.settingsService.tapToClick) {
        if (_lastTapTime != null &&
            _lastTapPos != null &&
            now.difference(_lastTapTime!).inMilliseconds < 350 &&
            (event.position - _lastTapPos!).distance < 30) {
          // Double click
          _performHaptic();
          widget.connectionService.sendMouseClick('left', 'double');
          _lastTapTime = null;
          _lastTapPos = null;
        } else {
          // Single left click
          _performHaptic();
          widget.connectionService.sendMouseClick('left', 'click');
          _lastTapTime = now;
          _lastTapPos = event.position;
        }
      } else if (_activePointers == 2) {
        // 2-finger tap = right click
        _performHaptic();
        widget.connectionService.sendMouseClick('right', 'click');
      }
    }

    _pointerPositions.remove(event.pointer);
    _activePointers = _pointerPositions.length;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _dragLockTimer?.cancel();
    if (_isDragging) {
      _isDragging = false;
      widget.connectionService.sendMouseClick('left', 'up');
    }
    _pointerPositions.remove(event.pointer);
    _activePointers = _pointerPositions.length;
  }

  void _performHaptic() {
    if (widget.settingsService.hapticsEnabled) {
      HapticFeedback.lightImpact();
    }
  }

  // --- Keyboard & Live Typing Methods ---

  void _onNativeTextChanged(String currentText) {
    if (_isCommandMode) {
      // In AI Command mode, do not inject individual keystrokes to active PC window
      setState(() {
        _previewText = currentText;
      });
      return;
    }

    if (currentText.length < _previousText.length) {
      final diff = _previousText.length - currentText.length;
      for (int i = 0; i < diff; i++) {
        widget.connectionService.sendKeyEvent('Backspace');
      }
      _performHaptic();
    } else if (currentText.length > _previousText.length) {
      final added = currentText.substring(_previousText.length);
      widget.connectionService.sendTextInput(added);
      _performHaptic();
    }
    _previousText = currentText;

    if (currentText.length > 80) {
      Future.microtask(() {
        if (mounted) {
          _inputController.clear();
          _previousText = '';
        }
      });
    }

    setState(() {
      _previewText = currentText;
    });
  }

  void _onSubmitted(String text) {
    _performHaptic();
    final clean = text.trim();
    if (_isCommandMode || clean.startsWith('/') || clean.startsWith('>')) {
      final cmd = clean.replaceFirst(RegExp(r'^[/>]'), '').trim();
      if (cmd.isNotEmpty) {
        widget.connectionService.sendVoiceCommand(cmd);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Executing: "$cmd"...')),
              ],
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      widget.connectionService.sendKeyEvent('Enter');
    }
    _inputController.clear();
    _previousText = '';
    setState(() {
      _previewText = '';
    });
    _inputFocusNode.requestFocus();
  }

  void _clearPreview() {
    _performHaptic();
    _inputController.clear();
    _previousText = '';
    setState(() {
      _previewText = '';
    });
  }

  void _sendKey(String key) {
    _performHaptic();
    final mods = <String>[];
    if (_isCtrlActive) mods.add('ctrl');
    if (_isAltActive) mods.add('alt');
    if (_isShiftActive) mods.add('shift');

    widget.connectionService.sendKeyEvent(key, modifiers: mods);

    if (_isShiftActive) {
      setState(() => _isShiftActive = false);
    }
  }

  void _sendSpace() {
    _performHaptic();
    widget.connectionService.sendKeyEvent('Space');
    final updated = '$_previewText ';
    _inputController.text = updated;
    _previousText = updated;
    setState(() {
      _previewText = updated;
    });
  }

  void _sendBackspace() {
    _performHaptic();
    widget.connectionService.sendKeyEvent('Backspace');
    if (_previewText.isNotEmpty) {
      final updated = _previewText.substring(0, _previewText.length - 1);
      _inputController.text = updated;
      _previousText = updated;
      setState(() {
        _previewText = updated;
      });
    }
  }

  void _sendEnter() {
    _performHaptic();
    widget.connectionService.sendKeyEvent('Enter');
    _inputController.clear();
    _previousText = '';
    setState(() {
      _previewText = '';
    });
  }

  void _sendUrduChar(String char) {
    _performHaptic();
    widget.connectionService.sendTextInput(char);
    final updated = '$_previewText$char';
    _inputController.text = updated;
    _previousText = updated;
    setState(() {
      _previewText = updated;
    });
  }

  // --- UI Builders ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.touch_app_rounded, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Mobile Kemo',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
            ),
            const Spacer(),
            if (widget.connectionService.isConnected) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${widget.connectionService.latencyMs}ms',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('Offline', style: TextStyle(fontSize: 11, color: Colors.red)),
              ),
            ],
          ],
        ),
        actions: [
          // Universal PC Zoom Controls (Zoom In, Zoom Out, Reset 100%)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2436) : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () {
                    _performHaptic();
                    widget.connectionService.sendShortcut('zoom_out');
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Icon(Icons.remove_rounded, size: 15),
                  ),
                ),
                InkWell(
                  onTap: () {
                    _performHaptic();
                    widget.connectionService.sendShortcut('zoom_reset');
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text('100%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
                InkWell(
                  onTap: () {
                    _performHaptic();
                    widget.connectionService.sendShortcut('zoom_in');
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Icon(Icons.add_rounded, size: 15),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.screen_share_rounded, color: Color(0xFF10B981)),
            tooltip: 'PC Touch Screen Mode',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TouchscreenScreen(
                    connectionService: widget.connectionService,
                    settingsService: widget.settingsService,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.mic_rounded, color: Colors.redAccent),
            tooltip: 'Kemo Voice Assistant',
            onPressed: () => _openVoiceAssistantSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Touchpad Settings',
            onPressed: () => _showSensitivityModal(context),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

            return Column(
              children: [
                // 1. Live Typed Preview Box (Only when typing to preserve vertical space in landscape)
                if (_previewText.isNotEmpty) _buildLivePreviewBox(isDark),

                // 2. Precision Mouse Touchpad Area (Takes ALL available space when collapsed, or remaining space)
                Expanded(
                  child: _buildTouchpadSurface(isDark),
                ),

                // 3. Expandable / Collapsible Bottom Mouse & Keyboard Controls Bar
                if (_bottomControlsExpanded) ...[
                  // Header / Collapse Bar
                  Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    color: isDark ? const Color(0xFF141722) : const Color(0xFFE5E9F0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.tune_rounded, size: 13, color: isDark ? Colors.white60 : Colors.black54),
                            const SizedBox(width: 6),
                            Text(
                              'Mouse & Keyboard Controls',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        InkWell(
                          onTap: () {
                            _performHaptic();
                            setState(() => _bottomControlsExpanded = false);
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Row(
                              children: [
                                Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: isDark ? Colors.white70 : Colors.black87),
                                const SizedBox(width: 2),
                                Text(
                                  'Hide',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // In Landscape: wrap controls in a responsive constrained container to prevent squishing trackpad
                  if (isLandscape)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: (constraints.maxHeight * 0.40).clamp(100.0, 140.0),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildClickButtons(isDark),
                            _buildFunctionKeysBar(isDark),
                            _buildInputBar(isDark),
                            if (_showUrduPalette) _buildUrduPalette(isDark),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    _buildClickButtons(isDark),
                    _buildFunctionKeysBar(isDark),
                    _buildInputBar(isDark),
                    if (_showUrduPalette) _buildUrduPalette(isDark),
                  ],
                ] else ...[
                  // Collapsed Obvious Bar to Expand Anytime
                  InkWell(
                    onTap: () {
                      _performHaptic();
                      setState(() => _bottomControlsExpanded = true);
                    },
                    child: Container(
                      height: 32,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1B202D) : const Color(0xFFDCE2EC),
                        border: Border(top: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: Colors.blueAccent),
                          const SizedBox(width: 6),
                          Text(
                            'Show Mouse Controls (Left/Right Click & Shortcuts)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLivePreviewBox(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF191D28) : const Color(0xFFEFF3F8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF2B3346) : const Color(0xFFCBD5E1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'LIVE TYPING PREVIEW',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const Spacer(),
              if (_previewText.isNotEmpty)
                InkWell(
                  onTap: _clearPreview,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.clear_rounded,
                          size: 14,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'Clear',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 24, maxHeight: 52),
            child: SingleChildScrollView(
              reverse: true,
              child: Text(
                _previewText.isEmpty
                    ? 'Type below — text streams to PC live...'
                    : _previewText,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: _previewText.isEmpty ? FontWeight.normal : FontWeight.w600,
                  color: _previewText.isEmpty
                      ? (isDark ? Colors.white30 : Colors.black38)
                      : (isDark ? Colors.white : Colors.black87),
                  fontStyle: _previewText.isEmpty ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTouchpadSurface(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF12141A) : const Color(0xFFE8ECF2),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _isDragging
                  ? Colors.amber.withValues(alpha: 0.9)
                  : (isDark ? const Color(0xFF262C3A) : const Color(0xFFCBD5E1)),
              width: _isDragging ? 2.5 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.touch_app_rounded,
                      size: 34,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.08),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Touchpad (Mouse Area)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.18)
                            : Colors.black.withValues(alpha: 0.18),
                      ),
                    ),
                  ],
                ),
              ),
              if (_isDragging)
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_outline, size: 13, color: Colors.black),
                          SizedBox(width: 4),
                          Text(
                            'Dragging...',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClickButtons(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: SizedBox(
              height: 44,
              child: Listener(
                onPointerDown: (_) {
                  _performHaptic();
                  setState(() => _isLeftButtonHeld = true);
                  widget.connectionService.sendMouseClick('left', 'down');
                },
                onPointerUp: (_) {
                  setState(() => _isLeftButtonHeld = false);
                  widget.connectionService.sendMouseClick('left', 'up');
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: _isLeftButtonHeld
                        ? Colors.blueAccent
                        : (isDark ? const Color(0xFF202532) : const Color(0xFFDCE2EC)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isLeftButtonHeld
                          ? Colors.blueAccent
                          : (isDark ? const Color(0xFF2E3648) : const Color(0xFFCCD6E0)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.mouse_outlined,
                        size: 15,
                        color: _isLeftButtonHeld ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isLeftButtonHeld ? 'Dragging...' : 'Left Click',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _isLeftButtonHeld ? Colors.white : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 44,
            width: 44,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? const Color(0xFF202532) : const Color(0xFFDCE2EC),
                foregroundColor: isDark ? Colors.white : Colors.black87,
                padding: EdgeInsets.zero,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isDark ? const Color(0xFF2E3648) : const Color(0xFFCCD6E0),
                  ),
                ),
              ),
              onPressed: () {
                _performHaptic();
                widget.connectionService.sendMouseClick('middle', 'click');
              },
              child: const Icon(Icons.circle_outlined, size: 15),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 5,
            child: SizedBox(
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? const Color(0xFF202532) : const Color(0xFFDCE2EC),
                  foregroundColor: isDark ? Colors.white : Colors.black87,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: isDark ? const Color(0xFF2E3648) : const Color(0xFFCCD6E0),
                    ),
                  ),
                ),
                onPressed: () {
                  _performHaptic();
                  widget.connectionService.sendMouseClick('right', 'click');
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.ads_click_rounded, size: 15),
                    SizedBox(width: 6),
                    Text('Right Click', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFunctionKeysBar(bool isDark) {
    return Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          // 1. Single Expandable Shortcuts Button
          Expanded(
            flex: 8,
            child: InkWell(
              onTap: () {
                _performHaptic();
                ExpandableShortcutSheet.show(
                  context,
                  connectionService: widget.connectionService,
                  settingsService: widget.settingsService,
                );
              },
              borderRadius: BorderRadius.circular(9),
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E283A) : const Color(0xFFE0E7FF),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF6366F1),
                    width: 1.1,
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.bolt_rounded,
                        size: 15,
                        color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF4F46E5),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '⚡ Shortcuts',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1E1B4B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // 2. Instant Backspace button
          Expanded(
            flex: 7,
            child: _keyPill('⌫ Back', _sendBackspace, isDark, highlight: true),
          ),
          const SizedBox(width: 6),

          // 3. Instant Enter button
          Expanded(
            flex: 6,
            child: _keyPill('↵ Enter', _sendEnter, isDark),
          ),
          const SizedBox(width: 6),

          // 4. Instant Urdu layout toggle
          Expanded(
            flex: 5,
            child: _keyPill(_showUrduPalette ? 'EN' : 'اردو', () {
              setState(() => _showUrduPalette = !_showUrduPalette);
            }, isDark, highlight: _showUrduPalette),
          ),
        ],
      ),
    );
  }

  Widget _keyPill(String label, VoidCallback onTap, bool isDark, {bool highlight = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: highlight
              ? Colors.amber.withValues(alpha: 0.25)
              : (isDark ? const Color(0xFF222735) : const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: highlight
                ? Colors.amber
                : (isDark ? const Color(0xFF333B4E) : const Color(0xFFCBD5E1)),
          ),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: highlight
                  ? (isDark ? Colors.amberAccent : Colors.amber.shade900)
                  : (isDark ? Colors.white70 : Colors.black87),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toggleKeyPill(String label, bool active, VoidCallback onTap, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? Colors.blueAccent
                : (isDark ? const Color(0xFF222735) : const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? Colors.blueAccent
                  : (isDark ? const Color(0xFF333B4E) : const Color(0xFFCBD5E1)),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161922) : const Color(0xFFF1F4F9),
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF262C3A) : const Color(0xFFCBD5E1),
          ),
        ),
      ),
      child: Row(
        children: [
          // AI Command / Live Typing Mode Toggle Pill
          InkWell(
            onTap: () {
              _performHaptic();
              setState(() {
                _isCommandMode = !_isCommandMode;
                _inputController.clear();
                _previousText = '';
                _previewText = '';
              });
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: _isCommandMode
                    ? Colors.blueAccent
                    : (isDark ? const Color(0xFF222736) : const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _isCommandMode
                      ? Colors.blueAccent
                      : (isDark ? const Color(0xFF333D52) : const Color(0xFFCBD5E1)),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isCommandMode ? Icons.terminal_rounded : Icons.keyboard_rounded,
                    size: 15,
                    color: _isCommandMode ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isCommandMode ? 'AI' : 'Type',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _isCommandMode ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _inputController,
              focusNode: _inputFocusNode,
              onChanged: _onNativeTextChanged,
              onSubmitted: _onSubmitted,
              textInputAction: TextInputAction.send,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: _isCommandMode
                    ? 'Type PC command (e.g. open this pc)...'
                    : 'Type live into PC / mic...',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                filled: true,
                fillColor: isDark ? const Color(0xFF0F1117) : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF262C3A) : const Color(0xFFCBD5E1),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: _isCommandMode ? Colors.blueAccent : Colors.lightBlue,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (_isCommandMode)
            IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(7),
                minimumSize: const Size(36, 36),
              ),
              icon: const Icon(Icons.send_rounded, size: 16),
              tooltip: 'Send Computer Command',
              onPressed: () => _onSubmitted(_inputController.text),
            )
          else
            IconButton(
              icon: Icon(
                _inputFocusNode.hasFocus ? Icons.keyboard_hide_outlined : Icons.keyboard_outlined,
                color: Colors.blueAccent,
              ),
              tooltip: 'Toggle Mobile Keyboard',
              onPressed: () {
                if (_inputFocusNode.hasFocus) {
                  _inputFocusNode.unfocus();
                } else {
                  _inputFocusNode.requestFocus();
                }
              },
            ),
          IconButton(
            icon: const Icon(
              Icons.mic_rounded,
              color: Colors.redAccent,
              size: 24,
            ),
            tooltip: 'Kemo Voice Assistant',
            onPressed: () => _openVoiceAssistantSheet(context),
          ),
        ],
      ),
    );
  }

  Widget _buildUrduPalette(bool isDark) {
    return Container(
      height: 145,
      padding: const EdgeInsets.all(6),
      color: isDark ? const Color(0xFF141720) : const Color(0xFFE2E8F0),
      child: Column(
        children: _urduLayout.map((row) {
          return Expanded(
            child: Row(
              children: row.map((char) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(1.5),
                    child: InkWell(
                      onTap: () => _sendUrduChar(char),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF202532) : Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isDark ? const Color(0xFF2D3546) : const Color(0xFFCBD5E1),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          char,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showSensitivityModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final sensitivity = widget.settingsService.sensitivity;
            final invert = widget.settingsService.invertScroll;
            final tapToClick = widget.settingsService.tapToClick;

            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Touchpad Settings',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Pointer Sensitivity', style: TextStyle(fontWeight: FontWeight.w500)),
                      Text('${sensitivity.toStringAsFixed(1)}x', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: sensitivity.clamp(0.4, 8.0),
                    min: 0.4,
                    max: 8.0,
                    divisions: 76,
                    label: '${sensitivity.toStringAsFixed(1)}x',
                    onChanged: (val) {
                      widget.settingsService.setSensitivity(val);
                      setModalState(() {});
                      setState(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Natural (Inverted) Scrolling'),
                    value: invert,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      widget.settingsService.setInvertScroll(val);
                      setModalState(() {});
                      setState(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Tap to Click'),
                    value: tapToClick,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      widget.settingsService.setTapToClick(val);
                      setModalState(() {});
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openVoiceAssistantSheet(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textController = TextEditingController();
    bool isListening = false;
    String accumulatedText = '';
    String feedbackText = 'Tap microphone to speak, or type any command below.';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            void sendCommand(String cmd) {
              final clean = cmd.trim();
              if (clean.isEmpty) return;
              if (widget.settingsService.hapticsEnabled) {
                HapticFeedback.mediumImpact();
              }
              final lower = clean.toLowerCase();
              if (lower == 'show desktop' || lower == 'desktop') {
                widget.connectionService.sendShortcut('desktop');
              } else if (lower == 'volume up' || lower == 'volume_up') {
                widget.connectionService.sendShortcut('volume_up');
              } else if (lower == 'volume down' || lower == 'volume_down') {
                widget.connectionService.sendShortcut('volume_down');
              } else if (lower == 'mute') {
                widget.connectionService.sendShortcut('mute');
              } else if (lower == 'close window') {
                widget.connectionService.sendShortcut('close_window');
              } else {
                widget.connectionService.sendVoiceCommand(clean);
              }
              Navigator.of(ctx).pop();
            }

            Future<void> toggleListening() async {
              if (isListening) {
                await _speech.stop();
                setSheetState(() {
                  isListening = false;
                  accumulatedText = textController.text.trim();
                  feedbackText = 'Listening paused. Tap mic to add more words, or tap Send.';
                });
                return;
              }

              // Preserve any existing text before starting new speech session
              accumulatedText = textController.text.trim();

              if (!_speechInitialized) {
                try {
                  _speechInitialized = await _speech.initialize(
                    onError: (err) {
                      setSheetState(() {
                        isListening = false;
                        feedbackText = 'Speech error: ${err.errorMsg}';
                      });
                    },
                    onStatus: (status) {
                      if (status == 'done' || status == 'notListening') {
                        setSheetState(() {
                          isListening = false;
                          accumulatedText = textController.text.trim();
                          if (accumulatedText.isNotEmpty) {
                            feedbackText = 'Speech paused. Tap mic to continue, or tap Send.';
                          }
                        });
                      }
                    },
                  );
                } catch (e) {
                  setSheetState(() {
                    feedbackText = 'Could not initialize speech: $e';
                  });
                }
              }

              if (_speechInitialized) {
                setSheetState(() {
                  isListening = true;
                  feedbackText = 'Listening continuously... Speak in Urdu or English!';
                });
                try {
                  await _speech.listen(
                    listenFor: const Duration(minutes: 2),
                    pauseFor: const Duration(seconds: 4),
                    partialResults: true,
                    cancelOnError: false,
                    onResult: (result) {
                      setSheetState(() {
                        final currentWords = result.recognizedWords.trim();
                        final fullText = accumulatedText.isNotEmpty
                            ? '$accumulatedText $currentWords'
                            : currentWords;
                        textController.text = fullText;
                        if (result.finalResult) {
                          accumulatedText = fullText;
                          feedbackText = 'Recognized: "$fullText"';
                        }
                      });
                    },
                  );
                } catch (e) {
                  setSheetState(() {
                    isListening = false;
                    feedbackText = 'Error starting listener: $e';
                  });
                }
              } else {
                setSheetState(() {
                  feedbackText = 'Microphone permission or speech recognition unavailable on device.';
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle Bar
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Title & Description
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.record_voice_over_rounded, color: Colors.blueAccent, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'Kemo Assistant (Voice & Type)',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Voice Continuous Dictation • Urdu • Roman Urdu • English',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Big Animated Pulse Microphone Button
                    GestureDetector(
                      onTap: toggleListening,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isListening ? Colors.redAccent : Colors.blueAccent,
                          boxShadow: [
                            BoxShadow(
                              color: (isListening ? Colors.redAccent : Colors.blueAccent)
                                  .withValues(alpha: isListening ? 0.5 : 0.25),
                              blurRadius: isListening ? 20 : 10,
                              spreadRadius: isListening ? 6 : 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                          color: Colors.white,
                          size: 38,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Feedback status text
                    Text(
                      feedbackText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isListening ? FontWeight.bold : FontWeight.normal,
                        color: isListening
                            ? Colors.redAccent
                            : (isDark ? Colors.white70 : Colors.black54),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Continuous Text Box with Clear & Send Buttons
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: textController,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Speak or type PC command here...',
                              hintStyle: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              filled: true,
                              fillColor: isDark ? const Color(0xFF141720) : const Color(0xFFF1F5F9),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: isDark ? const Color(0xFF2B3346) : const Color(0xFFCBD5E1),
                                ),
                              ),
                              suffixIcon: textController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 18),
                                      tooltip: 'Clear command',
                                      onPressed: () {
                                        setSheetState(() {
                                          textController.clear();
                                          accumulatedText = '';
                                        });
                                      },
                                    )
                                  : null,
                            ),
                            onSubmitted: (val) => sendCommand(val),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.send_rounded, size: 20),
                          tooltip: 'Send Command to PC',
                          onPressed: () => sendCommand(textController.text),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Quick Action Chips Header
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'QUICK STARTER COMMANDS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: isDark ? Colors.white38 : Colors.black45,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Quick Starter Chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildQuickChip(
                          '🖥️ Open This PC',
                          () => sendCommand('open this pc'),
                          isDark,
                        ),
                        _buildQuickChip(
                          '🌐 Chrome kholo',
                          () => sendCommand('Chrome kholo'),
                          isDark,
                        ),
                        _buildQuickChip(
                          '📁 Downloads kholo',
                          () => sendCommand('Downloads kholo'),
                          isDark,
                        ),
                        _buildQuickChip(
                          '📂 Desktop kholo',
                          () => sendCommand('Desktop kholo'),
                          isDark,
                        ),
                        _buildQuickChip(
                          '📁 Naya folder banao',
                          () => sendCommand('create folder My Folder'),
                          isDark,
                        ),
                        _buildQuickChip(
                          '📝 Notepad kholo',
                          () => sendCommand('Notepad kholo'),
                          isDark,
                        ),
                        _buildQuickChip(
                          '🔍 Search Lahore weather',
                          () => sendCommand('Google par search karo Lahore weather'),
                          isDark,
                        ),
                        _buildQuickChip(
                          '🔊 Volume barhao',
                          () => sendCommand('Volume up'),
                          isDark,
                        ),
                        _buildQuickChip(
                          '🔇 Awaz band (Mute)',
                          () => sendCommand('mute'),
                          isDark,
                        ),
                        _buildQuickChip(
                          '🪟 Show Desktop',
                          () => sendCommand('show desktop'),
                          isDark,
                        ),
                        _buildQuickChip(
                          '❌ Window band karo',
                          () => sendCommand('close window'),
                          isDark,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQuickChip(String label, VoidCallback onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF191D28) : const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? const Color(0xFF2C3549) : const Color(0xFFCBD5E1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
      ),
    );
  }
}
