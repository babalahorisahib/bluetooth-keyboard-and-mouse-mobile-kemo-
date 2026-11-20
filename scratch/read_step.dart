import 'dart:io';
import 'dart:convert';

void main() {
  var file = File(r'C:\Users\Administrator\.gemini\antigravity\brain\54670178-9eb0-4591-ab90-9aa619e89fb4\.system_generated\logs\transcript.jsonl');
  var lines = file.readAsLinesSync();
  for (var l in lines) {
    if (l.trim().isEmpty) continue;
    try {
      var m = jsonDecode(l);
      if (m['step_index'] >= 14485 && m['step_index'] <= 14502) {
        print('=== Step ${m["step_index"]} [${m["source"]}] [${m["type"]}] ===');
        var content = (m['content'] ?? '').toString();
        if (content.length > 500) {
          print(content.substring(0, 500) + '... (truncated)');
        } else {
          print(content);
        }
      }
    } catch (e) {
      // ignore
    }
  }
}
