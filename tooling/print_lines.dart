import 'dart:io';

void main(List<String> args) {
  if (args.length < 3) {
    print('Usage: dart print_lines.dart <path> <start> <end>');
    exit(1);
  }
  final path = args[0];
  final start = int.parse(args[1]);
  final end = int.parse(args[2]);
  final file = File(path);
  if (!file.existsSync()) {
    print('File not found: $path');
    exit(2);
  }
  final lines = file.readAsLinesSync();
  for (var i = start; i <= end && i <= lines.length; i++) {
    print('${i}: ${lines[i-1]}');
  }
}
