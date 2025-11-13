import 'package:flutter/widgets.dart';

/// Simple shared navigator key so widgets built outside the Navigator subtree
/// can perform navigation (dev tools, global error handlers, etc.).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
