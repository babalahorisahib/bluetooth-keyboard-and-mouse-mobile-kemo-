import 'dart:io';
import 'dart:convert';

void main() {
  var file = File(r'C:\Users\Administrator\.gemini\antigravity\brain\54670178-9eb0-4591-ab90-9aa619e89fb4\.system_generated\logs\transcript.jsonl');
  var lines = file.readAsLinesSync();
  for (var i = lines.length - 8; i < lines.length; i++) {
    if (i < 0) continue;
    var m = jsonDecode(lines[i]);
    var content = (m['content'] ?? '').toString();
    var firstLine = content.split('\n').first;
    if (firstLine.length > 80) firstLine = firstLine.substring(0, 80);
    print('${m["step_index"]} | ${m["source"]} | ${m["type"]} | $firstLine');
  }
}
