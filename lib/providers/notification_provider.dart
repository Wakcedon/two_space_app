import 'package:riverpod/riverpod.dart';

// Notification state
final notificationsEnabledProvider = StateProvider<bool>((ref) {
  return true; // default enabled
});

// Sound notifications provider
final soundNotificationsProvider = StateProvider<bool>((ref) {
  return true; // default enabled
});
