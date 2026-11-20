import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/connection_service.dart';
import '../services/settings_service.dart';
import '../touchpad/expandable_shortcut_sheet.dart';

class TouchscreenScreen extends StatefulWidget {
  final ConnectionService connectionService;
  final SettingsService settingsService;

  const TouchscreenScreen({
    super.key,
    required this.connectionService,
    required this.settingsService,
  });

  @override
  State<TouchscreenScreen> createState() => _TouchscreenScreenState();
}

class _TouchscreenScreenState extends State<TouchscreenScreen> with WidgetsBindingObserver {
  StreamSubscription<Uint8List>? _frameSubscription;
  Uint8List? _lastFrame;
  int _fpsCounter = 0;
  int _currentFps = 0;
  Timer? _fpsTimer;
  Timer? _streamWatchdogTimer;
  bool _isAppInBackground = false;

  // Ultra-HD mode: true = 92 quality (4:4:4 chroma, razor-sharp text) / 18 fps; false = 82 quality / 22 fps
  bool _isUltraHd = true;

  // Orientation state: null = Auto (Sensor-driven), true = Manual Landscape, false = Manual Portrait
  bool? _isManualLandscape;
  bool? _lastPhysicalLandscape;

  // Screen Zoom & Pan State (Full touch gestures)
  double _zoomScale = 1.0;
  Offset _zoomPanOffset = Offset.zero;
  double? _initialPinchDistance;
  double _initialZoomScale = 1.0;
  Offset? _initialPinchCenter;

  // Overlay state
  bool _showToolbar = true;
  bool _showKeyboard = false;
  bool _controlsExpanded = true;

  // Speech to Text state
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechInitialized = false;

  // Virtual Keyboard Input State
  late final TextEditingController _textController;
  final FocusNode _focusNode = FocusNode();
  String _previousText = '';
  DateTime _lastFrameTimestamp = DateTime.now();

  // Mouse Buttons State (Supports Click, Double Click, and Hold-to-Drag)
  bool _isLeftButtonHeld = false;

  // Direct Touchscreen State (Unified Portrait + Landscape Touch Control Surface)
  final Map<int, Offset> _screenTouchPointers = {};
  Offset? _screenPointerDownPos;
  bool _screenIsDragging = false;
  Timer? _screenLongPressTimer;
  bool _screenLongPressed = false;
  Offset? _lastScreenTapPos;
  Offset? _lastScreenTapNorm;
  int _lastScreenTapTime = 0;
  Offset? _screenLastMultiCenter;
  Rect _screenRenderedRect = Rect.zero;
  bool _wasPinching = false;
  bool _isTwoFingerPinch = false;
  bool _isTwoFingerScroll = false;
  bool _showUrduPalette = false;
  bool _showFunctionKeys = false;
  Size _remoteScreenSize = const Size(1920, 1080);
  bool _screenSizeDetected = false;

  static const List<List<String>> _urduLayout = [
    ['آ', 'ا', 'ب', 'پ', 'ت', 'ٹ', 'ث', 'ج', 'چ', 'ح', 'خ'],
    ['د', 'ڈ', 'ذ', 'ر', 'ڑ', 'ز', 'ژ', 'س', 'ش', 'ص', 'ض'],
    ['ط', 'ظ', 'ع', 'غ', 'ف', 'ق', 'ک', 'گ', 'ل', 'م', 'ن'],
    ['ں', 'و', 'ہ', 'ھ', 'ء', 'ی', 'ے', 'ئ', '۔', '؟', '،'],
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _textController = TextEditingController();

    // Hardware Keyboard listener on FocusNode
    _focusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.backspace) {
          _performHaptic();
          widget.connectionService.sendKeyEvent('Backspace');
          return KeyEventResult.handled;
        } else if (event.logicalKey == LogicalKeyboardKey.enter) {
          _performHaptic();
          widget.connectionService.sendKeyEvent('Enter');
          return KeyEventResult.handled;
        } else if (event.logicalKey == LogicalKeyboardKey.tab) {
          _performHaptic();
          widget.connectionService.sendKeyEvent('Tab');
          return KeyEventResult.handled;
        } else if (event.logicalKey == LogicalKeyboardKey.escape) {
          _performHaptic();
          widget.connectionService.sendKeyEvent('Escape');
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };

    widget.connectionService.addListener(_onConnectionServiceChanged);
    _startStream();
    if (widget.connectionService.isConnected &&
        !widget.connectionService.isAudioStreaming &&
        !widget.connectionService.isAudioMuted) {
      widget.connectionService.startAudioStream();
    }

    // FPS Meter Timer
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentFps = _fpsCounter;
          _fpsCounter = 0;
        });
      }
    });

    _startWatchdog();
  }

  void _startWatchdog() {
    _streamWatchdogTimer?.cancel();
    _streamWatchdogTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _isAppInBackground) return;
      if (widget.connectionService.isConnected) {
        final elapsed = DateTime.now().difference(_lastFrameTimestamp).inMilliseconds;
        if (elapsed > 2000) {
          _lastFrameTimestamp = DateTime.now();
          _startStream();
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _isAppInBackground = true;
      _streamWatchdogTimer?.cancel();
      widget.connectionService.stopScreenStream();
    } else if (state == AppLifecycleState.resumed) {
      _isAppInBackground = false;
      _lastFrameTimestamp = DateTime.now();
      if (mounted && widget.connectionService.isConnected) {
        _startStream();
      }
      _startWatchdog();
    }
  }

  void _onConnectionServiceChanged() {
    if (!mounted) return;
    if (widget.connectionService.isConnected && _lastFrame == null) {
      _startStream();
    }
    if (widget.connectionService.isConnected &&
        !widget.connectionService.isAudioStreaming &&
        !widget.connectionService.isAudioMuted) {
      widget.connectionService.startAudioStream();
    }
    setState(() {});
  }

    Size? _parseJpegDimensions(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
    int i = 2;
    while (i + 8 < bytes.length) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = bytes[i + 1];
      if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
        final h = (bytes[i + 5] << 8) | bytes[i + 6];
        final w = (bytes[i + 7] << 8) | bytes[i + 8];
        if (w > 0 && h > 0) return Size(w.toDouble(), h.toDouble());
        return null;
      }
      if (marker == 0xD9 || marker == 0xDA) break;
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2;
        continue;
      }
      if (i + 3 >= bytes.length) break;
      final len = (bytes[i + 2] << 8) | bytes[i + 3];
      i += 2 + len;
    }
    return null;
  }

  void _detectFrameSize(Uint8List bytes) {
    if (_screenSizeDetected) return;
    _screenSizeDetected = true;
    decodeImageFromList(bytes).then((img) {
      if (mounted && img.width > 0 && img.height > 0) {
        setState(() {
          _remoteScreenSize = Size(img.width.toDouble(), img.height.toDouble());
        });
      }
    }).catchError((_) {});
  }

  void _startStream() {
    if (_isAppInBackground) return;
    final quality = _isUltraHd ? 75 : 68;
    final maxWidth = _isUltraHd ? 1280 : 960;
    final fps = _isUltraHd ? 16 : 14;

    _frameSubscription?.cancel();
    _frameSubscription = widget.connectionService.screenStream.listen(
      (frame) {
        if (mounted && frame.isNotEmpty) {
          final parsedSize = _parseJpegDimensions(frame);
          if (parsedSize != null && parsedSize != _remoteScreenSize) {
            _remoteScreenSize = parsedSize;
            _screenSizeDetected = true;
          } else {
            _detectFrameSize(frame);
          }
          setState(() {
            _lastFrame = frame;
            _lastFrameTimestamp = DateTime.now();
            _fpsCounter++;
          });
          widget.connectionService.sendFrameAck();
        }
      },
      onError: (_) {},
    );

    if (widget.connectionService.isConnected) {
      widget.connectionService.startScreenStream(
        quality: quality,
        maxWidth: maxWidth,
        fps: fps,
      );
    } else {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && widget.connectionService.isConnected && _lastFrame == null) {
          _startStream();
        }
      });
    }
  }

  void _toggleOrientation() {
    _performHaptic();
    final isDeviceLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final currentLandscape = _isManualLandscape ?? isDeviceLandscape;
    final next = !currentLandscape;
    setState(() {
      _isManualLandscape = next;
      _zoomPanOffset = Offset.zero;
      _zoomScale = 1.0;
    });

    if (next) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  // --- SCREEN ZOOM & PAN CONTROLS ---
  Offset _clampPanOffset(Offset pan, double scale) {
    if (scale <= 1.0) return Offset.zero;
    // Allow panning up to the edge of the zoomed content
    final maxPanX = _screenRenderedRect.width * (scale - 1.0) / 2.0 + 30;
    final maxPanY = _screenRenderedRect.height * (scale - 1.0) / 2.0 + 30;
    return Offset(
      pan.dx.clamp(-maxPanX, maxPanX),
      pan.dy.clamp(-maxPanY, maxPanY),
    );
  }

  void _zoomIn() {
    _performHaptic();
    final newScale = (_zoomScale + 0.5).clamp(1.0, 4.0);
    setState(() {
      _zoomScale = newScale;
      _zoomPanOffset = _clampPanOffset(_zoomPanOffset, newScale);
    });
  }

  void _zoomOut() {
    _performHaptic();
    final newScale = (_zoomScale - 0.5).clamp(1.0, 4.0);
    setState(() {
      _zoomScale = newScale;
      if (newScale <= 1.0) {
        _zoomPanOffset = Offset.zero;
      } else {
        _zoomPanOffset = _clampPanOffset(_zoomPanOffset, newScale);
      }
    });
  }

  void _resetZoom() {
    _performHaptic();
    setState(() {
      _zoomScale = 1.0;
      _zoomPanOffset = Offset.zero;
    });
  }

  void _openVoiceDialog() {
    _performHaptic();
    final textCtrl = TextEditingController();
    bool isListening = false;
    String feedback = 'Tap Mic to speak (Urdu / English) or type command below';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161924),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            void toggleListen() async {
              _performHaptic();
              if (isListening) {
                await _speech.stop();
                setSheetState(() {
                  isListening = false;
                  feedback = 'Speech paused. Tap send or edit text.';
                });
                return;
              }

              if (!_speechInitialized) {
                try {
                  _speechInitialized = await _speech.initialize(
                    onError: (err) {
                      setSheetState(() {
                        isListening = false;
                        feedback = 'Mic error: ${err.errorMsg}';
                      });
                    },
                    onStatus: (status) {
                      if (status == 'done' || status == 'notListening') {
                        setSheetState(() => isListening = false);
                      }
                    },
                  );
                } catch (e) {
                  setSheetState(() {
                    feedback = 'Speech initialization failed: $e';
                  });
                }
              }

              if (_speechInitialized) {
                setSheetState(() {
                  isListening = true;
                  feedback = 'Listening... Speak in Urdu or English!';
                });
                try {
                  await _speech.listen(
                    listenFor: const Duration(seconds: 45),
                    pauseFor: const Duration(seconds: 3),
                    partialResults: true,
                    cancelOnError: false,
                    onResult: (result) {
                      setSheetState(() {
                        final spoken = result.recognizedWords.trim();
                        textCtrl.text = spoken;
                        if (result.finalResult) {
                          feedback = 'Recognized: "$spoken"';
                        }
                      });
                    },
                  );
                } catch (e) {
                  setSheetState(() {
                    isListening = false;
                    feedback = 'Error: $e';
                  });
                }
              } else {
                setSheetState(() {
                  feedback = 'Microphone permission or speech recognition unavailable on device.';
                });
              }
            }

            void submitCommand(String val) {
              final cmd = val.trim();
              if (cmd.isNotEmpty) {
                _performHaptic();
                widget.connectionService.sendVoiceCommand(cmd);
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('⚡ Executing: "$cmd"...'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 14,
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mic_rounded, color: Colors.redAccent, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Kemo Voice & AI Assistant',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Big Animated Pulse Microphone Button
                    GestureDetector(
                      onTap: toggleListen,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 66,
                        height: 66,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isListening ? Colors.redAccent : Colors.blueAccent,
                          boxShadow: [
                            BoxShadow(
                              color: (isListening ? Colors.redAccent : Colors.blueAccent)
                                  .withOpacity(isListening ? 0.6 : 0.25),
                              blurRadius: isListening ? 18 : 8,
                              spreadRadius: isListening ? 4 : 1,
                            ),
                          ],
                        ),
                        child: Icon(
                          isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      feedback,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: isListening ? Colors.redAccent : Colors.white70,
                        fontWeight: isListening ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Text Input + Send Button
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: textCtrl,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Speak or type PC command (Urdu / English)...',
                              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              filled: true,
                              fillColor: const Color(0xFF202534),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onSubmitted: submitCommand,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.send_rounded, size: 18),
                          onPressed: () => submitCommand(textCtrl.text),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _commandChip('🖥️ Desktop', 'show desktop', ctx, shortcutAction: 'desktop'),
                        _commandChip('🔒 Lock PC', 'lock pc', ctx, shortcutAction: 'lock'),
                        _commandChip('🔊 Volume Up', 'volume up', ctx, shortcutAction: 'volume_up'),
                        _commandChip('🔇 Mute', 'mute', ctx, shortcutAction: 'mute'),
                        _commandChip('🌐 Chrome', 'open chrome', ctx),
                        _commandChip('💻 This PC', 'open this pc', ctx),
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

  Widget _commandChip(String label, String cmd, BuildContext ctx, {String? shortcutAction}) {
    return ActionChip(
      backgroundColor: const Color(0xFF22293A),
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      onPressed: () {
        _performHaptic();
        if (shortcutAction != null) {
          widget.connectionService.sendShortcut(shortcutAction);
        } else {
          widget.connectionService.sendVoiceCommand(cmd);
        }
        Navigator.of(ctx).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚡ Executed: "$label"'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }

  void _performHaptic({bool heavy = false}) {
    if (widget.settingsService.hapticsEnabled) {
      if (heavy) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.lightImpact();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.connectionService.removeListener(_onConnectionServiceChanged);
    _screenLongPressTimer?.cancel();
    _fpsTimer?.cancel();
    _streamWatchdogTimer?.cancel();
    _frameSubscription?.cancel();
    widget.connectionService.stopScreenStream();

    // Restore orientations and system bars
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // =========================================================================
  // VIRTUAL KEYBOARD & BACKSPACE HANDLING (100% Guaranteed on Android)
  // =========================================================================

  void _onKeyboardTextChanged(String currentVal) {
    if (currentVal.length < _previousText.length) {
      // User pressed backspace
      final backspaceCount = _previousText.length - currentVal.length;
      for (int i = 0; i < backspaceCount; i++) {
        _performHaptic();
        widget.connectionService.sendKeyEvent('Backspace');
      }
    } else if (currentVal.length > _previousText.length) {
      // User typed characters
      final newText = currentVal.substring(_previousText.length);
      _performHaptic();
      widget.connectionService.sendTextInput(newText);
    }
    _previousText = currentVal;

    if (currentVal.length > 80) {
      Future.microtask(() {
        if (mounted) {
          _textController.clear();
          _previousText = '';
        }
      });
    }
  }

  // =========================================================================
  // DIRECT TOUCHSCREEN LOGIC (PC Screen View)
  // =========================================================================

  void _updateScreenRect(BoxConstraints constraints) {
    final containerSize = Size(constraints.maxWidth, constraints.maxHeight);
    final fitted = applyBoxFit(BoxFit.contain, _remoteScreenSize, containerSize);
    final offsetX = (containerSize.width - fitted.destination.width) / 2;
    final offsetY = (containerSize.height - fitted.destination.height) / 2;
    _screenRenderedRect = Rect.fromLTWH(offsetX, offsetY, fitted.destination.width, fitted.destination.height);
  }

  Offset? _normalizeScreenCoords(Offset localPos) {
    if (_screenRenderedRect.width <= 0 || _screenRenderedRect.height <= 0) {
      return null;
    }
    final feedCenter = _screenRenderedRect.center;
    final unzoomedX = feedCenter.dx + (localPos.dx - _zoomPanOffset.dx - feedCenter.dx) / _zoomScale;
    final unzoomedY = feedCenter.dy + (localPos.dy - _zoomPanOffset.dy - feedCenter.dy) / _zoomScale;

    final dx = (unzoomedX - _screenRenderedRect.left) / _screenRenderedRect.width;
    final dy = (unzoomedY - _screenRenderedRect.top) / _screenRenderedRect.height;
    return Offset(
      dx.clamp(0.0, 1.0),
      dy.clamp(0.0, 1.0),
    );
  }

  void _handleScreenPointerDown(PointerDownEvent event) {
    _screenTouchPointers[event.pointer] = event.localPosition;

    if (_screenTouchPointers.length == 1) {
      _screenPointerDownPos = event.localPosition;
      _screenIsDragging = false;
      _screenLongPressed = false;

      // 450ms timer for right-click on long-press (Step 5)
      _screenLongPressTimer?.cancel();
      _screenLongPressTimer = Timer(const Duration(milliseconds: 450), () {
        if (_screenTouchPointers.length == 1 && !_screenIsDragging && !_wasPinching) {
          _screenLongPressed = true;
          final norm = _normalizeScreenCoords(event.localPosition);
          if (norm != null) {
            _performHaptic(heavy: true);
            widget.connectionService.sendTouchEvent('right_click', norm.dx, norm.dy);
          }
        }
      });
    } else if (_screenTouchPointers.length == 2) {
      _screenLongPressTimer?.cancel();
      // Ensure any active drag from the first finger is released immediately
      if (_screenIsDragging) {
        final norm = _normalizeScreenCoords(event.localPosition);
        if (norm != null) {
          widget.connectionService.sendTouchEvent('up', norm.dx, norm.dy);
        }
        _screenIsDragging = false;
      }
      _wasPinching = true;
      _isTwoFingerPinch = false;
      _isTwoFingerScroll = false;
      final list = _screenTouchPointers.values.toList();
      _initialPinchDistance = (list[0] - list[1]).distance;
      _initialZoomScale = _zoomScale;
      _initialPinchCenter = _computeScreenCenter();
      _screenLastMultiCenter = _initialPinchCenter;
    }
  }

  void _handleScreenPointerMove(PointerMoveEvent event) {
    _screenTouchPointers[event.pointer] = event.localPosition;

    if (_screenTouchPointers.length == 1 && !_wasPinching) {
      final norm = _normalizeScreenCoords(event.localPosition);
      if (norm != null) {
        final dist = _screenPointerDownPos != null
            ? (event.localPosition - _screenPointerDownPos!).distance
            : 0.0;
        // Standard Android touch slop (18dp) prevents micro-jitters during taps from triggering drags
        if (dist > 18.0) {
          _screenLongPressTimer?.cancel();
          if (!_screenIsDragging) {
            _screenIsDragging = true;
            widget.connectionService.sendTouchEvent('down', norm.dx, norm.dy);
          }
          widget.connectionService.sendTouchEvent('move', norm.dx, norm.dy);
        }
      }
    } else if (_screenTouchPointers.length == 2) {
      _screenLongPressTimer?.cancel();
      _wasPinching = true;
      final list = _screenTouchPointers.values.toList();
      final currentDist = (list[0] - list[1]).distance;
      final center = _computeScreenCenter();
      if (center == null || _initialPinchDistance == null) return;

      final distDelta = (currentDist - _initialPinchDistance!).abs();
      final centerDelta = _initialPinchCenter != null
          ? (center - _initialPinchCenter!).distance
          : 0.0;

      // Classify gesture: Pinch zoom vs Two-finger scroll / pan
      if (!_isTwoFingerPinch && !_isTwoFingerScroll) {
        if (distDelta > 16.0 && distDelta > centerDelta * 0.8) {
          _isTwoFingerPinch = true;
        } else if (centerDelta > 10.0 && centerDelta > distDelta) {
          _isTwoFingerScroll = true;
        }
      }

      if (_isTwoFingerPinch) {
        // Pinch zoom (clamped 1.0x to 4.0x)
        if (_initialPinchDistance! > 10) {
          final distRatio = currentDist / _initialPinchDistance!;
          final newScale = (_initialZoomScale * distRatio).clamp(1.0, 4.0);
          final oldScale = _zoomScale;
          setState(() {
            if (newScale <= 1.0) {
              _zoomScale = 1.0;
              _zoomPanOffset = Offset.zero;
            } else if ((newScale - oldScale).abs() > 0.005) {
              // Scale pan offset proportionally to keep pinch center stable
              _zoomPanOffset = _clampPanOffset(
                _zoomPanOffset * (newScale / oldScale),
                newScale,
              );
              _zoomScale = newScale;
            }
          });
        }
      } else if (_isTwoFingerScroll) {
        // Two-finger Pan when zoomed in, or Natural Scroll when at 1.0x
        if (_zoomScale > 1.05 && _screenLastMultiCenter != null) {
          final panDelta = center - _screenLastMultiCenter!;
          setState(() {
            _zoomPanOffset = _clampPanOffset(_zoomPanOffset + panDelta, _zoomScale);
          });
        } else if (_screenLastMultiCenter != null) {
          final dx = center.dx - _screenLastMultiCenter!.dx;
          final dy = center.dy - _screenLastMultiCenter!.dy;
          // Natural continuous mouse-wheel scrolling:
          // Moving upward (dy < 0) = scroll document downward (negative wheel)
          // Moving downward (dy > 0) = scroll document upward (positive wheel)
          // Moving left/right = horizontal scroll
          if (dy.abs() > 0.5 || dx.abs() > 0.5) {
            widget.connectionService.sendMouseScroll(dx * 2.5, dy * 2.5);
          }
        }
      }
      _screenLastMultiCenter = center;
    }
  }

  void _handleScreenPointerUp(PointerUpEvent event) {
    _screenTouchPointers.remove(event.pointer);
    _screenLongPressTimer?.cancel();

    if (_screenTouchPointers.isEmpty) {
      _initialPinchDistance = null;
      _initialPinchCenter = null;

      // Prevent zoom/scroll gestures from triggering accidental remote clicks or drags
      if (_wasPinching) {
        if (_screenIsDragging) {
          final norm = _normalizeScreenCoords(event.localPosition);
          if (norm != null) {
            widget.connectionService.sendTouchEvent('up', norm.dx, norm.dy);
          }
        }
        _wasPinching = false;
        _isTwoFingerPinch = false;
        _isTwoFingerScroll = false;
        _screenIsDragging = false;
        _screenLongPressed = false;
        _screenLastMultiCenter = null;
        _screenPointerDownPos = null;
        return;
      }

      final norm = _normalizeScreenCoords(event.localPosition);
      if (norm != null) {
        if (_screenIsDragging) {
          widget.connectionService.sendTouchEvent('up', norm.dx, norm.dy);
        } else if (!_screenLongPressed) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final isDoubleTap = (now - _lastScreenTapTime < 350) &&
              _lastScreenTapPos != null &&
              (event.localPosition - _lastScreenTapPos!).distance < 30.0;

          if (isDoubleTap) {
            _lastScreenTapTime = 0;
            _performHaptic();
            // Send at _lastScreenTapNorm coordinates to guarantee double-click hits exact same pixel!
            final targetNorm = _lastScreenTapNorm ?? norm;
            widget.connectionService.sendTouchEvent('double_tap', targetNorm.dx, targetNorm.dy);
          } else {
            _lastScreenTapTime = now;
            _lastScreenTapPos = event.localPosition;
            _lastScreenTapNorm = norm;
            _performHaptic();
            widget.connectionService.sendTouchEvent('tap', norm.dx, norm.dy);
          }
        }
      }
      _screenIsDragging = false;
      _screenLongPressed = false;
      _screenLastMultiCenter = null;
      _screenPointerDownPos = null;
      _isTwoFingerPinch = false;
      _isTwoFingerScroll = false;
    }
  }

  void _handleScreenPointerCancel(PointerCancelEvent event) {
    _screenLongPressTimer?.cancel();
    _screenTouchPointers.remove(event.pointer);
    if (_screenTouchPointers.isEmpty) {
      if (_screenIsDragging) {
        final norm = _normalizeScreenCoords(event.localPosition);
        if (norm != null) {
          widget.connectionService.sendTouchEvent('up', norm.dx, norm.dy);
        }
      }
      _wasPinching = false;
      _isTwoFingerPinch = false;
      _isTwoFingerScroll = false;
      _initialPinchDistance = null;
      _initialPinchCenter = null;
      _screenIsDragging = false;
      _screenLongPressed = false;
      _screenLastMultiCenter = null;
      _screenPointerDownPos = null;
    }
  }

  Offset? _computeScreenCenter() {
    if (_screenTouchPointers.length < 2) return null;
    final list = _screenTouchPointers.values.toList();
    return Offset((list[0].dx + list[1].dx) / 2, (list[0].dy + list[1].dy) / 2);
  }

  // =========================================================================
  // BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    final isDeviceLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    if (_lastPhysicalLandscape != null && _lastPhysicalLandscape != isDeviceLandscape) {
      // Physical device was rotated! Release any manual locks and reset zoom/pan to guarantee screen visibility
      _isManualLandscape = null;
      _zoomPanOffset = Offset.zero;
      _zoomScale = 1.0;
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    _lastPhysicalLandscape = isDeviceLandscape;
    final effectiveLandscape = _isManualLandscape ?? isDeviceLandscape;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      body: Stack(
        children: [
          // Main Body
          Positioned.fill(
            child: effectiveLandscape ? _buildLandscapeLayout() : _buildPortraitLayout(),
          ),

          // Floating Top Toolbar (Generous safe padding, never pushed into phone curved corners)
          if (_showToolbar)
            Positioned(
              top: 0,
              left: 14,
              right: 14,
              child: SafeArea(
                top: true,
                left: true,
                right: true,
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _buildTopToolbar(effectiveLandscape),
                ),
              ),
            )
          else
            Positioned(
              top: 0,
              right: 18,
              child: SafeArea(
                top: true,
                right: true,
                bottom: false,
                left: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, right: 4),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _performHaptic();
                      setState(() => _showToolbar = true);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141824).withOpacity(0.95),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blueAccent.withOpacity(0.6)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.menu_rounded, color: Colors.blueAccent, size: 16),
                          SizedBox(width: 4),
                          Text(
                            'Menu',
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

        ],
      ),
    );
  }

  // --- RESPONSIVE KEYBOARD PANEL (Occupies ~40-50% in Portrait, auto-sized in Landscape) ---
  Widget _buildKeyboardPanel(BoxConstraints constraints, {required bool isLandscape}) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF141824),
        border: Border(top: BorderSide(color: Colors.white24, width: 1.2)),
        boxShadow: [
          BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, -3)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Primary Typing Bar: Back, Enter, Live Input, Urdu Toggle, Fn Toggle, Keys, Close
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: const BoxDecoration(
              color: Color(0xFF1B202E),
              border: Border(bottom: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                _quickBarButton(
                  icon: Icons.backspace_rounded,
                  label: 'Back',
                  color: Colors.amberAccent,
                  onTap: () {
                    _performHaptic();
                    widget.connectionService.sendKeyEvent('Backspace');
                  },
                ),
                const SizedBox(width: 5),
                _quickBarButton(
                  icon: Icons.keyboard_return_rounded,
                  label: 'Enter',
                  color: Colors.blueAccent,
                  onTap: () {
                    _performHaptic();
                    widget.connectionService.sendKeyEvent('Enter');
                  },
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF11141E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blueAccent.withOpacity(0.5)),
                    ),
                    child: TextField(
                      controller: _textController,
                      focusNode: _focusNode,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: _showUrduPalette ? 'اردو typing active...' : 'Type English / اردو live...',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: InputBorder.none,
                        isDense: true,
                        prefixIcon: const Icon(Icons.edit_note_rounded, color: Colors.blueAccent, size: 16),
                      ),
                      onChanged: _onKeyboardTextChanged,
                      onSubmitted: (_) {
                        _performHaptic();
                        widget.connectionService.sendKeyEvent('Enter');
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                InkWell(
                  onTap: () {
                    _performHaptic();
                    setState(() => _showUrduPalette = !_showUrduPalette);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    decoration: BoxDecoration(
                      color: _showUrduPalette ? Colors.green : const Color(0xFF262C3E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _showUrduPalette ? Colors.greenAccent : Colors.white24),
                    ),
                    child: Text(
                      'اردو',
                      style: TextStyle(
                        color: _showUrduPalette ? Colors.white : Colors.greenAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                InkWell(
                  onTap: () {
                    _performHaptic();
                    setState(() => _showFunctionKeys = !_showFunctionKeys);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
                    decoration: BoxDecoration(
                      color: _showFunctionKeys ? Colors.indigoAccent : const Color(0xFF262C3E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _showFunctionKeys ? Colors.indigo : Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Fn',
                          style: TextStyle(
                            color: _showFunctionKeys ? Colors.white : Colors.indigoAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Icon(
                          _showFunctionKeys ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          size: 14,
                          color: _showFunctionKeys ? Colors.white : Colors.indigoAccent,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                _quickBarButton(
                  icon: Icons.bolt_rounded,
                  label: 'Keys',
                  color: const Color(0xFF38BDF8),
                  onTap: () => ExpandableShortcutSheet.show(
                    context,
                    connectionService: widget.connectionService,
                    settingsService: widget.settingsService,
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () {
                    _performHaptic();
                    _focusNode.unfocus();
                    setState(() {
                      _showKeyboard = false;
                      _showUrduPalette = false;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close_rounded, color: Colors.redAccent, size: 16),
                        SizedBox(width: 2),
                        Text(
                          'Close',
                          style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 2. Collapsible Function Keys Strip (Hidden unless Fn is clicked)
          if (_showFunctionKeys)
            Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              color: const Color(0xFF141722),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _funcKeyPill('Esc', () => widget.connectionService.sendKeyEvent('Escape')),
                  _funcKeyPill('Tab', () => widget.connectionService.sendKeyEvent('Tab')),
                  _funcKeyPill('Ctrl+C', () => widget.connectionService.sendShortcut('copy')),
                  _funcKeyPill('Ctrl+V', () => widget.connectionService.sendShortcut('paste')),
                  _funcKeyPill('Ctrl+Z', () => widget.connectionService.sendShortcut('undo')),
                  _funcKeyPill('Ctrl+A', () => widget.connectionService.sendShortcut('select_all')),
                  _funcKeyPill('Win', () => widget.connectionService.sendKeyEvent('Meta')),
                  _funcKeyPill('Alt', () => widget.connectionService.sendKeyEvent('Alt')),
                  _funcKeyPill('Space', () => widget.connectionService.sendKeyEvent('Space')),
                  _funcKeyPill('←', () => widget.connectionService.sendKeyEvent('ArrowLeft')),
                  _funcKeyPill('↑', () => widget.connectionService.sendKeyEvent('ArrowUp')),
                  _funcKeyPill('↓', () => widget.connectionService.sendKeyEvent('ArrowDown')),
                  _funcKeyPill('→', () => widget.connectionService.sendKeyEvent('ArrowRight')),
                ],
              ),
            ),
          // 3. Urdu Character Palette (Only visible when toggled)
          if (_showUrduPalette)
            SizedBox(
              height: isLandscape ? 120 : 180,
              child: _buildUrduGrid(),
            ),
        ],
      ),
    );
  }

  Widget _buildUrduGrid() {
    return Container(
      padding: const EdgeInsets.all(4),
      color: const Color(0xFF10131B),
      child: Column(
        children: _urduLayout.map((row) {
          return Expanded(
            child: Row(
              children: row.map((char) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(1.0),
                    child: InkWell(
                      onTap: () {
                        _performHaptic();
                        widget.connectionService.sendTextInput(char);
                        final cur = _textController.text;
                        _textController.text = '$cur$char';
                        _previousText = _textController.text;
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C2232),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          char,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
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

  Widget _funcKeyPill(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.5),
      child: InkWell(
        onTap: () {
          _performHaptic();
          onTap();
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF222838),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  // --- LANDSCAPE: Immersive Touchscreen with Responsive Expandable Bottom Controls ---
  Widget _buildLandscapeLayout() {
    final topInset = MediaQuery.of(context).padding.top;
    final topToolbarSpacing = _showToolbar ? SizedBox(height: topInset + 46) : const SizedBox(height: 2);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_showKeyboard) {
          return Column(
            children: [
              topToolbarSpacing,
              Expanded(
                child: LayoutBuilder(
                  builder: (context, screenConstraints) {
                    _updateScreenRect(screenConstraints);
                    return _buildScreenFeed(screenConstraints);
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: _buildKeyboardPanel(constraints, isLandscape: true),
              ),
            ],
          );
        }

        return Column(
          children: [
            topToolbarSpacing,
            Expanded(
              child: LayoutBuilder(
                builder: (context, screenConstraints) {
                  _updateScreenRect(screenConstraints);
                  return _buildScreenFeed(screenConstraints);
                },
              ),
            ),
            if (_showFunctionKeys)
              SafeArea(
                top: false,
                bottom: false,
                child: _buildFunctionKeysStrip(),
              ),
            const SizedBox(height: 2),
            SafeArea(
              top: false,
              child: _controlsExpanded
                  ? _buildLandscapeControlsBar()
                  : _buildCollapsedControlsBar(),
            ),
          ],
        );
      },
    );
  }

  // --- PORTRAIT: Direct PC Touchscreen using Full Screen Space with Docked Typing & Responsive Controls ---
  Widget _buildPortraitLayout() {
    final topInset = MediaQuery.of(context).padding.top;
    final topToolbarSpacing = _showToolbar ? SizedBox(height: topInset + 46) : SizedBox(height: topInset + 4);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            topToolbarSpacing,

            // 1. Live PC Screen occupying all available touchscreen space (identical robust path as Landscape)
            Expanded(
              child: LayoutBuilder(
                builder: (context, screenConstraints) {
                  _updateScreenRect(screenConstraints);
                  return _buildScreenFeed(screenConstraints);
                },
              ),
            ),

            // Optional Typing Bar docked below the screen feed when active
            if (_showKeyboard) ...[
              SafeArea(
                top: false,
                bottom: false,
                child: _buildCompactTypingBar(),
              ),
              if (_showUrduPalette)
                SafeArea(
                  top: false,
                  bottom: false,
                  child: SizedBox(
                    height: 140,
                    child: _buildUrduGrid(),
                  ),
                ),
            ],

            if (_showFunctionKeys)
              SafeArea(
                top: false,
                bottom: false,
                child: _buildFunctionKeysStrip(),
              ),

            const SizedBox(height: 2),

            // 2. Compact Bottom Controls Bar (Physical Clicks, Zoom, Sensitivity Slider, Shortcuts)
            SafeArea(
              top: false,
              child: _controlsExpanded
                  ? _buildPortraitControlsBar()
                  : _buildCollapsedControlsBar(),
            ),
          ],
        );
      },
    );
  }

  // --- DOCKED COMPACT TYPING BAR (Directly below PC Screen Feed in Portrait) ---
  Widget _buildCompactTypingBar() {
    return Container(
      height: 42,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF141824),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Backspace
            InkWell(
              onTap: () {
                _performHaptic();
                widget.connectionService.sendKeyEvent('Backspace');
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2433),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.backspace_rounded, size: 16, color: Colors.redAccent),
              ),
            ),
            const SizedBox(width: 4),

            // Enter
            InkWell(
              onTap: () {
                _performHaptic();
                widget.connectionService.sendKeyEvent('Enter');
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2433),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.keyboard_return_rounded, size: 16, color: Colors.greenAccent),
              ),
            ),
            const SizedBox(width: 6),

            // Text Field for live typing
            SizedBox(
              width: 140,
              height: 32,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F121A),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white10),
                ),
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  cursorColor: Colors.blueAccent,
                  decoration: const InputDecoration(
                    hintText: 'Type to PC...',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 11),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 7),
                  ),
                  onChanged: _onKeyboardTextChanged,
                  onSubmitted: (text) {
                    _onKeyboardTextChanged(text);
                    widget.connectionService.sendKeyEvent('Enter');
                  },
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Urdu Palette Toggle
            InkWell(
              onTap: () {
                _performHaptic();
                setState(() => _showUrduPalette = !_showUrduPalette);
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: BoxDecoration(
                  color: _showUrduPalette ? Colors.teal : const Color(0xFF1F2433),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _showUrduPalette ? Colors.tealAccent : Colors.white12),
                ),
                child: Text(
                  'اردو',
                  style: TextStyle(
                    color: _showUrduPalette ? Colors.white : Colors.tealAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),

            // Fn strip toggle
            _buildFnToggleButton(),
            const SizedBox(width: 4),

            // Keys shortcut pill
            _quickActionPill(
              icon: Icons.bolt_rounded,
              label: 'Keys',
              color: Colors.amberAccent,
              onTap: () => ExpandableShortcutSheet.show(
                context,
                connectionService: widget.connectionService,
                settingsService: widget.settingsService,
              ),
            ),
            const SizedBox(width: 4),

            // Close button
            InkWell(
              onTap: () {
                _performHaptic();
                _focusNode.unfocus();
                setState(() {
                  _showKeyboard = false;
                  _showUrduPalette = false;
                });
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.close_rounded, size: 16, color: Colors.redAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- BOTTOM CONTROLS HELPER WIDGETS ---
  Widget _buildLeftDragButton() {
    return Listener(
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _isLeftButtonHeld ? Colors.blueAccent : const Color(0xFF262C3E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _isLeftButtonHeld ? Colors.blueAccent : Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_rounded, size: 14, color: _isLeftButtonHeld ? Colors.white : Colors.blueAccent),
            const SizedBox(width: 4),
            Text(_isLeftButtonHeld ? 'Drag' : 'Left', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildCollapseButton() {
    return InkWell(
      onTap: () {
        _performHaptic();
        setState(() => _controlsExpanded = false);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.white),
            SizedBox(width: 2),
            Text('Hide', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildPointerSpeedSlider() {
    final sens = widget.settingsService.sensitivity;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2433),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          const Icon(Icons.speed_rounded, size: 14, color: Colors.blueAccent),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: Colors.blueAccent,
                inactiveTrackColor: Colors.white12,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: sens.clamp(0.4, 6.0),
                min: 0.4,
                max: 6.0,
                divisions: 28,
                onChanged: (val) {
                  widget.settingsService.setSensitivity(val);
                  setState(() {});
                },
              ),
            ),
          ),
          Text(
            '${sens.toStringAsFixed(1)}x',
            style: const TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // --- FN STRIP TOGGLE BUTTON & FUNCTION KEYS STRIP ---
  Widget _buildFnToggleButton() {
    return InkWell(
      onTap: () {
        _performHaptic();
        setState(() => _showFunctionKeys = !_showFunctionKeys);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: _showFunctionKeys ? Colors.indigoAccent : const Color(0xFF1E2436),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _showFunctionKeys ? Colors.indigo : Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Fn',
              style: TextStyle(
                color: _showFunctionKeys ? Colors.white : Colors.indigoAccent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              _showFunctionKeys ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
              size: 13,
              color: _showFunctionKeys ? Colors.white : Colors.indigoAccent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFunctionKeysStrip() {
    return Container(
      height: 36,
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF141722),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _funcKeyPill('Esc', () => widget.connectionService.sendKeyEvent('Escape')),
          _funcKeyPill('Tab', () => widget.connectionService.sendKeyEvent('Tab')),
          _funcKeyPill('Ctrl+C', () => widget.connectionService.sendShortcut('copy')),
          _funcKeyPill('Ctrl+V', () => widget.connectionService.sendShortcut('paste')),
          _funcKeyPill('Ctrl+Z', () => widget.connectionService.sendShortcut('undo')),
          _funcKeyPill('Ctrl+A', () => widget.connectionService.sendShortcut('select_all')),
          _funcKeyPill('Win', () => widget.connectionService.sendKeyEvent('Meta')),
          _funcKeyPill('Alt', () => widget.connectionService.sendKeyEvent('Alt')),
          _funcKeyPill('Space', () => widget.connectionService.sendKeyEvent('Space')),
          _funcKeyPill('←', () => widget.connectionService.sendKeyEvent('ArrowLeft')),
          _funcKeyPill('↑', () => widget.connectionService.sendKeyEvent('ArrowUp')),
          _funcKeyPill('↓', () => widget.connectionService.sendKeyEvent('ArrowDown')),
          _funcKeyPill('→', () => widget.connectionService.sendKeyEvent('ArrowRight')),
        ],
      ),
    );
  }

  // --- PORTRAIT BOTTOM CONTROLS BAR (Responsive Two-Tier: Zero Clipping, All 11 Controls) ---
  Widget _buildPortraitControlsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF141824),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tier 1: Mouse Clicks + Zoom Controls + Fn Toggle + Collapse Toggle
          // Wrapped in FittedBox to guarantee 0 overflow on ANY screen size
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLeftDragButton(),
                const SizedBox(width: 5),
                _quickActionPill(
                  icon: Icons.adjust_rounded,
                  label: 'Mid',
                  color: Colors.white70,
                  onTap: () {
                    _performHaptic();
                    widget.connectionService.sendMouseClick('middle', 'click');
                  },
                ),
                const SizedBox(width: 5),
                _quickActionPill(
                  icon: Icons.ads_click_rounded,
                  label: 'Right',
                  color: const Color(0xFF10B981),
                  onTap: () {
                    _performHaptic(heavy: true);
                    widget.connectionService.sendMouseClick('right', 'click');
                  },
                ),
                const SizedBox(width: 5),
                _buildZoomControlsPill(),
                const SizedBox(width: 5),
                _buildFnToggleButton(),
                const SizedBox(width: 5),
                _buildCollapseButton(),
              ],
            ),
          ),
          const SizedBox(height: 5),
          // Tier 2: Pointer Speed / Sensitivity Slider + Keyboard + Shortcuts
          Row(
            children: [
              Expanded(child: _buildPointerSpeedSlider()),
              const SizedBox(width: 8),
              _quickActionPill(
                icon: Icons.keyboard_rounded,
                label: 'Keybd',
                color: const Color(0xFF38BDF8),
                onTap: () {
                  setState(() => _showKeyboard = true);
                  _focusNode.requestFocus();
                },
              ),
              const SizedBox(width: 6),
              _quickActionPill(
                icon: Icons.bolt_rounded,
                label: 'Keys',
                color: Colors.amberAccent,
                onTap: () => ExpandableShortcutSheet.show(
                  context,
                  connectionService: widget.connectionService,
                  settingsService: widget.settingsService,
                ),
              ),
              const SizedBox(width: 6),
              _quickActionPill(
                icon: widget.connectionService.isMicActive ? Icons.mic_rounded : Icons.mic_off_rounded,
                label: 'Mic',
                color: widget.connectionService.isMicActive ? const Color(0xFFEF4444) : Colors.white70,
                onTap: () {
                  _performHaptic();
                  widget.connectionService.toggleMic();
                  setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- LANDSCAPE BOTTOM CONTROLS BAR (Single-Row Immersive Bar with All 11 Controls) ---
  Widget _buildLandscapeControlsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      margin: const EdgeInsets.fromLTRB(6, 0, 6, 3),
      decoration: BoxDecoration(
        color: const Color(0xFF141824).withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLeftDragButton(),
            const SizedBox(width: 4),
            _quickActionPill(
              icon: Icons.adjust_rounded,
              label: 'Mid',
              color: Colors.white70,
              onTap: () {
                _performHaptic();
                widget.connectionService.sendMouseClick('middle', 'click');
              },
            ),
            const SizedBox(width: 4),
            _quickActionPill(
              icon: Icons.ads_click_rounded,
              label: 'Right',
              color: const Color(0xFF10B981),
              onTap: () {
                _performHaptic(heavy: true);
                widget.connectionService.sendMouseClick('right', 'click');
              },
            ),
            const SizedBox(width: 4),
            _buildZoomControlsPill(),
            const SizedBox(width: 4),
            SizedBox(
              width: 130,
              child: _buildPointerSpeedSlider(),
            ),
            const SizedBox(width: 4),
            _buildFnToggleButton(),
            const SizedBox(width: 4),
            _quickActionPill(
              icon: Icons.keyboard_rounded,
              label: 'Keybd',
              color: const Color(0xFF38BDF8),
              onTap: () {
                setState(() => _showKeyboard = true);
                _focusNode.requestFocus();
              },
            ),
            const SizedBox(width: 4),
            _quickActionPill(
              icon: Icons.bolt_rounded,
              label: 'Keys',
              color: Colors.amberAccent,
              onTap: () => ExpandableShortcutSheet.show(
                context,
                connectionService: widget.connectionService,
                settingsService: widget.settingsService,
              ),
            ),
            const SizedBox(width: 4),
            _quickActionPill(
              icon: widget.connectionService.isMicActive ? Icons.mic_rounded : Icons.mic_off_rounded,
              label: 'Mic',
              color: widget.connectionService.isMicActive ? const Color(0xFFEF4444) : Colors.white70,
              onTap: () {
                _performHaptic();
                widget.connectionService.toggleMic();
                setState(() {});
              },
            ),
            const SizedBox(width: 4),
            _buildCollapseButton(),
          ],
        ),
      ),
    );
  }

  // --- COLLAPSED CONTROLS MINI-PILL ---
  Widget _buildCollapsedControlsBar() {
    final sens = widget.settingsService.sensitivity;
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF141824).withOpacity(0.94),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLeftDragButton(),
                const SizedBox(width: 4),
                _quickActionPill(
                  icon: Icons.ads_click_rounded,
                  label: 'Right',
                  color: const Color(0xFF10B981),
                  onTap: () {
                    _performHaptic(heavy: true);
                    widget.connectionService.sendMouseClick('right', 'click');
                  },
                ),
                const SizedBox(width: 4),
                // Compact Speed Indicator & Quick Toggle Pill
                InkWell(
                  onTap: () {
                    _performHaptic();
                    setState(() => _controlsExpanded = true);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2433),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blueAccent.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.speed_rounded, size: 13, color: Colors.blueAccent),
                        const SizedBox(width: 3),
                        Text(
                          '${sens.toStringAsFixed(1)}x',
                          style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _buildZoomControlsPill(),
                const SizedBox(width: 4),
                _buildFnToggleButton(),
                const SizedBox(width: 4),
                _quickActionPill(
                  icon: Icons.keyboard_rounded,
                  label: 'Keybd',
                  color: const Color(0xFF38BDF8),
                  onTap: () {
                    setState(() => _showKeyboard = true);
                    _focusNode.requestFocus();
                  },
                ),
                const SizedBox(width: 4),
                _quickActionPill(
                  icon: widget.connectionService.isMicActive ? Icons.mic_rounded : Icons.mic_off_rounded,
                  label: 'Mic',
                  color: widget.connectionService.isMicActive ? const Color(0xFFEF4444) : Colors.white70,
                  onTap: () {
                    _performHaptic();
                    widget.connectionService.toggleMic();
                    setState(() {});
                  },
                ),
                const SizedBox(width: 4),
                // Expand / More Button (100% visible, cannot be clipped)
                InkWell(
                  onTap: () {
                    _performHaptic();
                    setState(() => _controlsExpanded = true);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blueAccent.withOpacity(0.5)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.keyboard_arrow_up_rounded, size: 16, color: Colors.blueAccent),
                        SizedBox(width: 2),
                        Text(
                          'More',
                          style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildZoomControlsPill() {
    final zoomPercent = (_zoomScale * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2436),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _zoomOut,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(Icons.remove_rounded, size: 14, color: Colors.white),
            ),
          ),
          InkWell(
            onTap: _resetZoom,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                '$zoomPercent%',
                style: TextStyle(
                  color: _zoomScale > 1.0 ? Colors.amberAccent : Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          InkWell(
            onTap: _zoomIn,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(Icons.add_rounded, size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionPill({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2436),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- SCREEN FEED WIDGET ---
  Widget _buildScreenFeed(BoxConstraints constraints) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handleScreenPointerDown,
      onPointerMove: _handleScreenPointerMove,
      onPointerUp: _handleScreenPointerUp,
      onPointerCancel: _handleScreenPointerCancel,
      child: _lastFrame == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.blueAccent),
                  const SizedBox(height: 14),
                  Text(
                    'Connecting to PC Screen...',
                    style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Ensure Mobile Kemo is running on PC',
                    style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _startStream,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Retry Connection', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            )
          : SizedBox.expand(
              child: ClipRect(
                child: Transform(
                  transform: Matrix4.identity()
                    ..translate(
                      (constraints.maxWidth / 2) * (1 - _zoomScale) + _zoomPanOffset.dx,
                      (constraints.maxHeight / 2) * (1 - _zoomScale) + _zoomPanOffset.dy,
                    )
                    ..scale(_zoomScale),
                  origin: Offset.zero,
                  child: Container(
                    color: Colors.black,
                    alignment: Alignment.center,
                    child: Image.memory(
                      _lastFrame!,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.low,
                      fit: BoxFit.contain,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Icon(Icons.broken_image_rounded, color: Colors.white38, size: 32),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  // --- FLOATING TOOLBAR ---
  Widget _buildTopToolbar(bool isLandscape) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF141824).withOpacity(0.95),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // 1. Back Button
            _iconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Exit',
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 4),

            // 2. FPS & Mode Badge (Tap to refresh video feed anytime)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _performHaptic();
                _startStream();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('⚡ Reconnecting screen stream...'),
                    duration: Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _currentFps > 0 ? Colors.greenAccent : Colors.amberAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$_currentFps',
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),

            // 3. Virtual Keyboard Toggle Button (ALWAYS visible & front!)
            _iconButton(
              icon: Icons.keyboard_rounded,
              tooltip: 'Toggle Virtual Keyboard',
              color: _showKeyboard ? Colors.blueAccent : const Color(0xFF38BDF8),
              onTap: () {
                setState(() {
                  _showKeyboard = !_showKeyboard;
                });
                if (_showKeyboard) {
                  _focusNode.requestFocus();
                } else {
                  _focusNode.unfocus();
                }
              },
            ),
            const SizedBox(width: 4),

            // 4. PC Shortcut Keys
            _iconButton(
              icon: Icons.bolt_rounded,
              tooltip: 'PC Shortcut Keys',
              color: Colors.amberAccent,
              onTap: () => ExpandableShortcutSheet.show(
                context,
                connectionService: widget.connectionService,
                settingsService: widget.settingsService,
              ),
            ),
            const SizedBox(width: 4),

            // 5. Screen Rotation (Portrait <-> Landscape)
            _iconButton(
              icon: isLandscape ? Icons.stay_current_portrait_rounded : Icons.screen_rotation_rounded,
              tooltip: isLandscape ? 'Portrait Mode' : 'Landscape Mode',
              color: Colors.white,
              onTap: _toggleOrientation,
            ),
            const SizedBox(width: 4),

            // 6. Groq AI Voice & Quick Action Assistant Button
            _iconButton(
              icon: Icons.mic_rounded,
              tooltip: 'Voice & AI Assistant',
              color: Colors.redAccent,
              onTap: _openVoiceDialog,
            ),
            const SizedBox(width: 4),

            // 7. PC Audio Streaming Toggle Button
            _iconButton(
              icon: widget.connectionService.isAudioStreaming
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              tooltip: widget.connectionService.isAudioStreaming
                  ? 'PC Audio: Streaming (Tap to Mute)'
                  : 'PC Audio: Muted (Tap to Stream)',
              color: widget.connectionService.isAudioStreaming
                  ? const Color(0xFF10B981)
                  : Colors.white60,
              onTap: () {
                _performHaptic();
                widget.connectionService.toggleAudioStream();
                final isStreaming = widget.connectionService.isAudioStreaming;
                if (mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isStreaming ? '🔊 PC Audio Streaming Active' : '🔇 PC Audio Muted',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: isStreaming ? const Color(0xFF10B981) : Colors.grey[800],
                    ),
                  );
                }
                setState(() {});
              },
            ),
            const SizedBox(width: 4),

            // 8. Ultra-HD / Sharp Text Toggle Button
            _iconButton(
              icon: _isUltraHd ? Icons.auto_awesome_rounded : Icons.hd_rounded,
              tooltip: _isUltraHd ? 'Ultra-HD Active' : 'HD Mode',
              color: _isUltraHd ? const Color(0xFF38BDF8) : Colors.white60,
              onTap: () {
                setState(() {
                  _isUltraHd = !_isUltraHd;
                });
                _startStream();
              },
            ),
            const SizedBox(width: 4),

            // 8. Screen Zoom Controls (In landscape where space permits)
            if (isLandscape) ...[
              _buildZoomControlsPill(),
              const SizedBox(width: 4),
            ],

            // 9. Hide Toolbar Button (Prominent, guaranteed tap response, never clipped)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _performHaptic();
                setState(() => _showToolbar = false);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.keyboard_arrow_up_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                    SizedBox(width: 2),
                    Text(
                      'Hide',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _performHaptic();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white12),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }

  Widget _quickBarButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF222838),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
