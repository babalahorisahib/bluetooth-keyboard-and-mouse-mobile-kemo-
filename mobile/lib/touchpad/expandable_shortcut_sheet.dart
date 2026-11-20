import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/connection_service.dart';
import '../services/settings_service.dart';

class ExpandableShortcutSheet {
  /// Opens the expandable shortcut menu. When any shortcut is tapped,
  /// it immediately triggers the action, performs haptics, and automatically
  /// collapses back into the button (closes the sheet).
  static Future<void> show(
    BuildContext context, {
    required ConnectionService connectionService,
    required SettingsService settingsService,
  }) {
    void haptic() {
      if (settingsService.hapticsEnabled) {
        HapticFeedback.lightImpact();
      }
    }

    void onKey(String key, {List<String> modifiers = const []}) {
      haptic();
      connectionService.sendKeyEvent(key, modifiers: modifiers);
      Navigator.of(context).pop();
    }

    void onShortcut(String action) {
      haptic();
      connectionService.sendShortcut(action);
      Navigator.of(context).pop();
    }

    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.75,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF141822),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 20,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle pill
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.bolt_rounded, color: Colors.blueAccent, size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'PC Shortcut Keys',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Tap to use & auto-close',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),

                const Divider(color: Colors.white12, height: 12),

                // Shortcuts content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Section 1: Core Essential Keys
                        _buildSectionHeader('Essential Keys', Icons.keyboard_rounded),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _actionChip('Esc', Icons.close_fullscreen_rounded, () => onKey('Escape'), highlight: true),
                            _actionChip('Tab ⇥', Icons.keyboard_tab_rounded, () => onKey('Tab')),
                            _actionChip('Enter ↵', Icons.keyboard_return_rounded, () => onKey('Enter'), primary: true),
                            _actionChip('Backspace ⌫', Icons.backspace_rounded, () => onKey('Backspace'), highlight: true),
                            _actionChip('Delete ⌦', Icons.delete_sweep_rounded, () => onKey('Delete')),
                            _actionChip('Win Start ⊞', Icons.window_rounded, () => onKey('Win'), primary: true),
                            _actionChip('Space ␣', Icons.space_bar_rounded, () => onKey('Space')),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // Section 2: Clipboard & Editing
                        _buildSectionHeader('Editing & Clipboard', Icons.content_copy_rounded),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _actionChip('Ctrl+C (Copy)', Icons.copy_rounded, () => onShortcut('copy')),
                            _actionChip('Ctrl+V (Paste)', Icons.paste_rounded, () => onShortcut('paste'), highlight: true),
                            _actionChip('Ctrl+X (Cut)', Icons.cut_rounded, () => onShortcut('cut')),
                            _actionChip('Ctrl+A (Select All)', Icons.select_all_rounded, () => onShortcut('select_all')),
                            _actionChip('Ctrl+Z (Undo)', Icons.undo_rounded, () => onShortcut('undo')),
                            _actionChip('Ctrl+Y (Redo)', Icons.redo_rounded, () => onShortcut('redo')),
                            _actionChip('Ctrl+S (Save)', Icons.save_rounded, () => onShortcut('save')),
                            _actionChip('Ctrl+F (Find)', Icons.search_rounded, () => onShortcut('find')),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // Section 3: Windows & App Management
                        _buildSectionHeader('Windows & Desktop', Icons.desktop_windows_rounded),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _actionChip('Alt+Tab (Switch)', Icons.swap_horiz_rounded, () => onShortcut('switch_window'), highlight: true),
                            _actionChip('Win+D (Desktop)', Icons.desktop_mac_rounded, () => onShortcut('desktop')),
                            _actionChip('Alt+F4 (Close)', Icons.cancel_rounded, () => onShortcut('close_window'), danger: true),
                            _actionChip('Win+Up (Maximize)', Icons.fullscreen_rounded, () => onShortcut('maximize')),
                            _actionChip('Win+M (Minimize)', Icons.minimize_rounded, () => onShortcut('minimize')),
                            _actionChip('PrtScn (Capture)', Icons.camera_alt_rounded, () => onShortcut('screenshot')),
                            _actionChip('F5 (Refresh)', Icons.refresh_rounded, () => onShortcut('refresh')),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // Section 4: Directional & Navigation
                        _buildSectionHeader('Arrow Keys & Navigation', Icons.navigation_rounded),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _actionChip('↑ Up', Icons.arrow_upward_rounded, () => onKey('ArrowUp')),
                            _actionChip('↓ Down', Icons.arrow_downward_rounded, () => onKey('ArrowDown')),
                            _actionChip('← Left', Icons.arrow_back_rounded, () => onKey('ArrowLeft')),
                            _actionChip('→ Right', Icons.arrow_forward_rounded, () => onKey('ArrowRight')),
                            _actionChip('Home', Icons.first_page_rounded, () => onKey('Home')),
                            _actionChip('End', Icons.last_page_rounded, () => onKey('End')),
                            _actionChip('Page Up', Icons.expand_less_rounded, () => onKey('PageUp')),
                            _actionChip('Page Down', Icons.expand_more_rounded, () => onKey('PageDown')),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // Section 5: Function Keys (F1 - F12)
                        _buildSectionHeader('Function Keys (F1 - F12)', Icons.functions_rounded),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (int i = 1; i <= 12; i++)
                              _actionChip('F$i', Icons.smart_button_rounded, () => onKey('F$i')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.blueAccent),
        const SizedBox(width: 6),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  static Widget _actionChip(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool primary = false,
    bool highlight = false,
    bool danger = false,
  }) {
    Color bg = const Color(0xFF222838);
    Color border = const Color(0xFF2F374E);
    Color text = Colors.white;

    if (danger) {
      bg = const Color(0xFF381A22);
      border = const Color(0xFF5E2734);
      text = const Color(0xFFFCA5A5);
    } else if (primary) {
      bg = const Color(0xFF1E3A8A);
      border = const Color(0xFF3B82F6);
      text = const Color(0xFF93C5FD);
    } else if (highlight) {
      bg = const Color(0xFF1E293B);
      border = const Color(0xFF38BDF8);
      text = const Color(0xFF7DD3FC);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border, width: 1.1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: text),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
