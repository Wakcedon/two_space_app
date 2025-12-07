import 'package:riverpod/riverpod.dart';

// Theme mode provider (light/dark/system)
final themeModeProvider = StateProvider<String>((ref) {
  return 'system';
});

// Primary color provider
final primaryColorProvider = StateProvider<int>((ref) {
  return 0xFF6200EE; // Default purple
});

// Pale violet mode provider
final paleVioletProvider = StateProvider<bool>((ref) {
  return false;
});
