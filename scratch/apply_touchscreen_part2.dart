import 'dart:io';

void main() {
  final file = File('mobile/lib/screens/touchscreen_screen.dart');
  var content = file.readAsStringSync().replaceAll('\r\n', '\n');

  // 1. Frame Listener
  const targetFrame = '''      (frame) {
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

  const replacementFrame = '''      (frame) {
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

  if (content.contains(targetFrame)) {
    content = content.replaceFirst(targetFrame, replacementFrame);
    print('1. Frame listener updated with fast JPEG parsing');
  } else {
    print('1. targetFrame not found');
  }

  // 2. Controls Bars
  final ctrlStart = content.indexOf('  // --- PORTRAIT BOTTOM CONTROLS BAR');
  final ctrlEnd = content.indexOf('  Widget _buildZoomControlsPill() {');

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
    print('2. Controls bars updated with full 11 controls, sensitivity slider, and responsive multi-tier');
  } else {
    print('2. Controls bars indices: ctrlStart=$ctrlStart, ctrlEnd=$ctrlEnd');
  }

  file.writeAsStringSync(content);
}
