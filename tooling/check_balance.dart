import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    print('Usage: dart check_balance.dart <path>');
    exit(1);
  }
  final path = args[0];
  final file = File(path);
  if (!file.existsSync()) {
    print('File not found: $path');
    exit(2);
  }
  final lines = file.readAsLinesSync();
  var paren = 0;
  var brace = 0;
  var brack = 0;
  final parenStack = <int>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    for (var r = 0; r < line.length; r++) {
      final c = line[r];
  if (c == '(') { paren++; parenStack.add(i+1); }
  if (c == ')') { paren--; if (parenStack.isNotEmpty) parenStack.removeLast(); }
      if (c == '{') brace++;
      if (c == '}') brace--;
      if (c == '[') brack++;
      if (c == ']') brack--;
      if (paren < 0) {
        print('Unmatched ) at line ${i+1}: ${line.trim()}');
        exit(3);
      }
      if (brace < 0) {
        print('Unmatched } at line ${i+1}: ${line.trim()}');
        exit(4);
      }
      if (brack < 0) {
        print('Unmatched ] at line ${i+1}: ${line.trim()}');
        exit(5);
      }
    }
    // Print diagnostics when parentheses count changes to help locate unclosed '('
    if (paren != 0) {
      print('After line ${i+1}, paren count = $paren');
    }
  }
  print('Final counts: ( ) = $paren, { } = $brace, [ ] = $brack');
  if (paren != 0 || brace != 0 || brack != 0) {
    print('Mismatch detected');
    if (parenStack.isNotEmpty) {
      print('Unclosed ( opened at lines: ${parenStack.join(', ')}');
    }
    exit(6);
  }
  print('Balanced');
}
