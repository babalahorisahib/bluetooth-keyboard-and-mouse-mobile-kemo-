import 'dart:io';

void main() {
  final f = File(r'C:\Users\Administrator\.gemini\antigravity\brain\54670178-9eb0-4591-ab90-9aa619e89fb4\.user_uploaded\media_1794552459398_11ed4052.jpg');
  print('File exists: ${f.existsSync()}, size: ${f.lengthSync()}');
}
