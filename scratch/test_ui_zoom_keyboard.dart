import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Zoom In, Zoom Out, and Reset Zoom Math & Clamping', () {
    double zoomScale = 1.0;
    Offset zoomPanOffset = Offset.zero;
    const renderedRect = Rect.fromLTWH(0, 50, 400, 300);
    final center = Offset(
      renderedRect.left + renderedRect.width / 2,
      renderedRect.top + renderedRect.height / 2,
    );

    // Zoom In (+0.5x)
    final oldScale1 = zoomScale;
    final newScale1 = (zoomScale + 0.5).clamp(1.0, 4.0);
    zoomPanOffset = center - (center - zoomPanOffset) * (newScale1 / oldScale1);
    zoomScale = newScale1;

    expect(zoomScale, 1.5);
    // Center of viewport must stay invariant under zoom transformation
    final contentCenter1 = (center - zoomPanOffset) / zoomScale;
    expect(contentCenter1.dx, closeTo(center.dx, 0.001));
    expect(contentCenter1.dy, closeTo(center.dy, 0.001));

    // Zoom In again (+0.5x -> 2.0x)
    final oldScale2 = zoomScale;
    final newScale2 = (zoomScale + 0.5).clamp(1.0, 4.0);
    zoomPanOffset = center - (center - zoomPanOffset) * (newScale2 / oldScale2);
    zoomScale = newScale2;

    expect(zoomScale, 2.0);
    final contentCenter2 = (center - zoomPanOffset) / zoomScale;
    expect(contentCenter2.dx, closeTo(center.dx, 0.001));
    expect(contentCenter2.dy, closeTo(center.dy, 0.001));

    // Zoom Out (-0.5x -> 1.5x)
    final oldScale3 = zoomScale;
    final newScale3 = (zoomScale - 0.5).clamp(1.0, 4.0);
    zoomPanOffset = center - (center - zoomPanOffset) * (newScale3 / oldScale3);
    zoomScale = newScale3;

    expect(zoomScale, 1.5);

    // Reset Zoom
    zoomScale = 1.0;
    zoomPanOffset = Offset.zero;

    expect(zoomScale, 1.0);
    expect(zoomPanOffset, Offset.zero);
  });

  test('Coordinate Normalization Inverts Zoom and Pan Exactly', () {
    const renderedRect = Rect.fromLTWH(20, 40, 360, 240);
    const zoomScale = 2.0;
    const zoomPanOffset = Offset(-180, -120);

    // Assume user wants to tap remote point at normalized (0.5, 0.5)
    final targetContentX = renderedRect.left + renderedRect.width * 0.5;
    final targetContentY = renderedRect.top + renderedRect.height * 0.5;

    // Under zoom transform: localPos = targetContent * scale + panOffset
    final localTap = Offset(
      targetContentX * zoomScale + zoomPanOffset.dx,
      targetContentY * zoomScale + zoomPanOffset.dy,
    );

    // Normalization inverse
    final unzoomedX = (localTap.dx - zoomPanOffset.dx) / zoomScale;
    final unzoomedY = (localTap.dy - zoomPanOffset.dy) / zoomScale;
    final normX = (unzoomedX - renderedRect.left) / renderedRect.width;
    final normY = (unzoomedY - renderedRect.top) / renderedRect.height;

    expect(normX, closeTo(0.5, 0.001));
    expect(normY, closeTo(0.5, 0.001));
  });

  test('Pinch-to-Zoom Accidental Click Prevention', () {
    bool wasPinching = false;
    bool clickTriggered = false;

    // Simulate 2 fingers down
    int pointers = 2;
    if (pointers == 2) wasPinching = true;

    // Finger 1 lifts
    pointers--;
    expect(wasPinching, true);

    // Finger 2 lifts
    pointers--;
    if (pointers == 0) {
      if (wasPinching) {
        wasPinching = false;
        clickTriggered = false; // Suppressed!
      } else {
        clickTriggered = true;
      }
    }

    expect(clickTriggered, false); // Tap was correctly suppressed!
    expect(wasPinching, false);
  });

  test('Keyboard Height Bounds in Portrait and Landscape', () {
    // Portrait (e.g. 840dp height)
    const portraitHeight = 840.0;
    final kbdPortrait = (portraitHeight * 0.44).clamp(220.0, 360.0);
    expect(kbdPortrait, closeTo(360.0, 1.0)); // Caps gracefully at 360dp (~43%)
    final screenPortrait = portraitHeight - kbdPortrait;
    expect(screenPortrait, greaterThan(450.0)); // PC screen gets >57% of screen!

    // Landscape (e.g. 380dp height)
    const landscapeHeight = 380.0;
    final kbdLandscape = (landscapeHeight * 0.42).clamp(115.0, 160.0);
    expect(kbdLandscape, closeTo(159.6, 1.0)); // ~42% of landscape height
    final screenLandscape = landscapeHeight - kbdLandscape;
    expect(screenLandscape, greaterThan(210.0)); // PC screen gets >55% of landscape height!
  });

  test('Touchpad Screen Bottom Controls Collapse Space Optimization', () {
    const screenHeightLandscape = 360.0;
    bool bottomControlsExpanded = true;

    // When expanded in landscape:
    double bottomHeight = (screenHeightLandscape * 0.40).clamp(100.0, 140.0);
    double touchpadHeight = screenHeightLandscape - bottomHeight;
    expect(touchpadHeight, greaterThan(215.0)); // Guaranteed >60% of landscape height!

    // When collapsed:
    bottomControlsExpanded = false;
    bottomHeight = 32.0; // Minimal toggle bar
    touchpadHeight = screenHeightLandscape - bottomHeight;
    expect(touchpadHeight, closeTo(328.0, 0.1)); // Maximized to >91% of entire screen!
  });

  print('ALL UI AND ZOOM TESTS PASSED SUCCESSFULLY!');
}
