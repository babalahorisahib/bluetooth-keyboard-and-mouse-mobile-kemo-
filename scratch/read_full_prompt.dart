import 'dart:io';
import 'dart:convert';

void main() {
  var file = File(r'C:\Users\Administrator\.gemini\antigravity\brain\54670178-9eb0-4591-ab90-9aa619e89fb4\.system_generated\logs\transcript_full.jsonl');
  var lines = file.readAsLinesSync();
  for (var l in lines) {
    if (l.trim().isEmpty) continue;
    try {
      var m = jsonDecode(l);
      if (m['step_index'] == 13988) {
        print(m['content']);
        break;
      }
    } catch (e) {}
  }
}
