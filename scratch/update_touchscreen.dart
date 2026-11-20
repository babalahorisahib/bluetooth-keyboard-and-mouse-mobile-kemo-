import 'dart:io';

void main() {
  final path = 'mobile/lib/screens/touchscreen_screen.dart';
  var content = File(path).readAsStringSync();

  // 1. Add _showFunctionKeys state
  if (!content.contains('bool _showFunctionKeys = false;')) {
    content = content.replaceFirst(
      'bool _showUrduPalette = false;',
      'bool _showUrduPalette = false;\n  bool _showFunctionKeys = false;',
    );
    print('Added _showFunctionKeys');
  }

  // 2. Add fast JPEG dimension parser
  const parserCode = '''
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
''';

  if (!content.contains('_parseJpegDimensions')) {
    content = content.replaceFirst(
      'void _detectFrameSize(Uint8List bytes) {',
      '$parserCode\n  void _detectFrameSize(Uint8List bytes) {',
    );
    print('Added _parseJpegDimensions');
  }

  // 3. In _startStream, update frame listener to use synchronous JPEG parsing
  final oldFrameListener = '''        (frame) {
          if (mounted) {
            _detectFrameSize(frame);
            setState(() {
              _lastFrame = frame;
              _lastFrameTimestamp = DateTime.now();
              _fpsCounter++;
            });
            widget.connectionService.sendFrameAck();
          }
        },''';

  final newFrameListener = '''        (frame) {
          if (mounted) {
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
        },''';

  if (content.contains(oldFrameListener)) {
    content = content.replaceFirst(oldFrameListener, newFrameListener);
    print('Updated frame listener with instant JPEG dimensions');
  } else {
    print('oldFrameListener not found');
  }

  // 4. In _toggleOrientation, reset zoom pan & scale
  final oldToggleOri = '''  void _toggleOrientation() {
    _performHaptic();
    final next = !_isLandscape;
    setState(() {
      _isLandscape = next;
    });''';

  final newToggleOri = '''  void _toggleOrientation() {
    _performHaptic();
    final next = !_isLandscape;
    setState(() {
      _isLandscape = next;
      _zoomPanOffset = Offset.zero;
      _zoomScale = 1.0;
    });''';

  if (content.contains(oldToggleOri)) {
    content = content.replaceFirst(oldToggleOri, newToggleOri);
    print('Updated _toggleOrientation with zoom reset');
  } else {
    print('oldToggleOri not found');
  }

  // 5. In _buildLandscapeLayout, add topToolbarSpacing
  final oldLandscapeLayout = '''    Widget _buildLandscapeLayout() {
      return SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (_showKeyboard) {
              return Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, screenConstraints) {
                        _updateScreenRect(screenConstraints);
                        return _buildScreenFeed(screenConstraints);
                      },
                    ),
                  ),
                  _buildKeyboardPanel(constraints, isLandscape: true),
                ],
              );
            }

            return Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, screenConstraints) {
                      _updateScreenRect(screenConstraints);
                      return _buildScreenFeed(screenConstraints);
                    },
                  ),
                ),''';

  final newLandscapeLayout = '''    Widget _buildLandscapeLayout() {
      final topToolbarSpacing = _showToolbar ? const SizedBox(height: 48) : const SizedBox(height: 2);
      return SafeArea(
        child: LayoutBuilder(
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
                  _buildKeyboardPanel(constraints, isLandscape: true),
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
                ),''';

  if (content.contains(oldLandscapeLayout)) {
    content = content.replaceFirst(oldLandscapeLayout, newLandscapeLayout);
    print('Updated _buildLandscapeLayout with topToolbarSpacing');
  } else {
    print('oldLandscapeLayout not found');
  }

  File(path).writeAsStringSync(content);
}
