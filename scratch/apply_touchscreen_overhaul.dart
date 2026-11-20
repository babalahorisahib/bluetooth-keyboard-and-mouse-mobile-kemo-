import 'dart:io';

void main() {
  final file = File('mobile/lib/screens/touchscreen_screen.dart');
  var content = file.readAsStringSync().replaceAll('\r\n', '\n');

  // 1. Frame Listener
  const oldFrame = '''        (frame) {
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

  const newFrame = '''        (frame) {
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

  if (content.contains(oldFrame)) {
    content = content.replaceFirst(oldFrame, newFrame);
    print('1. Frame listener updated with fast JPEG dimension parser');
  } else {
    print('1. oldFrame not found');
  }

  // 2. Landscape Layout topToolbarSpacing
  const oldLandscape = '''  Widget _buildLandscapeLayout() {
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

  const newLandscape = '''  Widget _buildLandscapeLayout() {
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

  if (content.contains(oldLandscape)) {
    content = content.replaceFirst(oldLandscape, newLandscape);
    print('2. Landscape layout updated with topToolbarSpacing');
  } else {
    print('2. oldLandscape not found');
  }

  // 3. Screen Feed Image rendering
  const oldFeedImage = '''          : ClipRect(
              child: Transform(
                transform: Matrix4.identity()
                  ..translate(_zoomPanOffset.dx, _zoomPanOffset.dy)
                  ..scale(_zoomScale),
                origin: Offset.zero,
                child: Image.memory(
                  _lastFrame!,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.low,
                  fit: BoxFit.contain,
                ),
              ),
            ),''';

  const newFeedImage = '''          : SizedBox.expand(
              child: ClipRect(
                child: Transform(
                  transform: Matrix4.identity()
                    ..translate(_zoomPanOffset.dx, _zoomPanOffset.dy)
                    ..scale(_zoomScale),
                  origin: Offset.zero,
                  child: Center(
                    child: SizedBox(
                      width: _screenRenderedRect.width > 0 ? _screenRenderedRect.width : null,
                      height: _screenRenderedRect.height > 0 ? _screenRenderedRect.height : null,
                      child: Image.memory(
                        _lastFrame!,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.low,
                        fit: BoxFit.fill,
                      ),
                    ),
                  ),
                ),
              ),
            ),''';

  if (content.contains(oldFeedImage)) {
    content = content.replaceFirst(oldFeedImage, newFeedImage);
    print('3. Screen feed updated to Center + SizedBox for 0-offset pixel alignment');
  } else {
    print('3. oldFeedImage not found');
  }

  // 4. Keyboard panel replacement (removes 'Live Keyboard Active' window, adds Fn toggle, compact docking)
  final kbStart = content.indexOf('  Widget _buildKeyboardPanel(BoxConstraints constraints, {required bool isLandscape}) {');
  final kbEnd = content.indexOf('  Widget _buildUrduGrid() {');

  if (kbStart != -1 && kbEnd != -1) {
    const newKeyboardPanel = '''  Widget _buildKeyboardPanel(BoxConstraints constraints, {required bool isLandscape}) {
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

''';
    content = content.replaceRange(kbStart, kbEnd, newKeyboardPanel);
    print('4. Keyboard panel overhauled: compact live typing, collapsible Fn, zero placeholder clutter');
  } else {
    print('4. Keyboard panel indices not found');
  }

  // 5. Controls Bars overhaul: Mouse Clicks, Zoom Controls, Sensitivity Slider, Keyboard, Keys, Collapse
  final ctrlStart = content.indexOf('  // --- PORTRAIT BOTTOM CONTROLS BAR (Expandable / Collapsible) ---');
  final ctrlEnd = content.indexOf('  // --- ZOOM CONTROLS PILL ---');

  if (ctrlStart != -1 && ctrlEnd != -1) {
    const newControlsBars = '''  // --- BOTTOM CONTROLS HELPER WIDGETS ---
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
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.white70),
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
            '\${sens.toStringAsFixed(1)}x',
            style: const TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold),
          ),
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
          // Tier 1: Mouse Clicks + Zoom Controls + Collapse Toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildLeftDragButton(),
              _quickActionPill(
                icon: Icons.adjust_rounded,
                label: 'Mid',
                color: Colors.white70,
                onTap: () {
                  _performHaptic();
                  widget.connectionService.sendMouseClick('middle', 'click');
                },
              ),
              _quickActionPill(
                icon: Icons.ads_click_rounded,
                label: 'Right',
                color: const Color(0xFF10B981),
                onTap: () {
                  _performHaptic(heavy: true);
                  widget.connectionService.sendMouseClick('right', 'click');
                },
              ),
              _buildZoomControlsPill(),
              _buildCollapseButton(),
            ],
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
            ],
          ),
        ],
      ),
    );
  }

  // --- LANDSCAPE BOTTOM CONTROLS BAR (Single-Row Immersive Bar with All 11 Controls) ---
  Widget _buildLandscapeControlsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF141824).withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildLeftDragButton(),
          _quickActionPill(
            icon: Icons.adjust_rounded,
            label: 'Mid',
            color: Colors.white70,
            onTap: () {
              _performHaptic();
              widget.connectionService.sendMouseClick('middle', 'click');
            },
          ),
          _quickActionPill(
            icon: Icons.ads_click_rounded,
            label: 'Right',
            color: const Color(0xFF10B981),
            onTap: () {
              _performHaptic(heavy: true);
              widget.connectionService.sendMouseClick('right', 'click');
            },
          ),
          _buildZoomControlsPill(),
          SizedBox(
            width: 140,
            child: _buildPointerSpeedSlider(),
          ),
          _quickActionPill(
            icon: Icons.keyboard_rounded,
            label: 'Keybd',
            color: const Color(0xFF38BDF8),
            onTap: () {
              setState(() => _showKeyboard = true);
              _focusNode.requestFocus();
            },
          ),
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
          _buildCollapseButton(),
        ],
      ),
    );
  }

  // --- COLLAPSED CONTROLS MINI-PILL ---
  Widget _buildCollapsedControlsBar() {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 12, bottom: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF141824).withOpacity(0.92),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
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
              _buildZoomControlsPill(),
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
              InkWell(
                onTap: () {
                  _performHaptic();
                  setState(() => _controlsExpanded = true);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blueAccent.withOpacity(0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.keyboard_arrow_up_rounded, size: 16, color: Colors.blueAccent),
                      SizedBox(width: 2),
                      Text('More', style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

''';
    content = content.replaceRange(ctrlStart, ctrlEnd, newControlsBars);
    print('5. Controls bars replaced with full 11 controls, sensitivity slider, and responsive multi-tier');
  } else {
    print('5. Controls bars indices not found: ctrlStart=$ctrlStart, ctrlEnd=$ctrlEnd');
  }

  file.writeAsStringSync(content);
  print('Finished overhaul script.');
}
