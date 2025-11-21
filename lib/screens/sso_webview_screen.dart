import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../config/environment.dart';
import '../services/auth_service.dart';

class SsoWebviewScreen extends StatefulWidget {
  final String idpId; // e.g. 'google' or 'yandex'
  const SsoWebviewScreen({super.key, required this.idpId});

  @override
  State<SsoWebviewScreen> createState() => _SsoWebviewScreenState();
}

class _SsoWebviewScreenState extends State<SsoWebviewScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  final AuthService _auth = AuthService();
  StreamSubscription<String?>? _urlSub;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) => _onUrlChanged(url),
        onNavigationRequest: (req) {
          _onUrlChanged(req.url);
          return NavigationDecision.navigate;
        },
        onPageFinished: (url) => setState(() => _loading = false),
      ));
    final hs = Environment.matrixHomeserverUrl.trim();
    var base = hs;
    if (base.isEmpty) base = ''; else if (!base.startsWith('http://') && !base.startsWith('https://')) base = 'https://' + base;
    final startUrl = Uri.parse(base + '/_matrix/client/v3/login/sso/redirect?idp=${widget.idpId}').toString();
    _controller.loadRequest(Uri.parse(startUrl));
  }

  void _onUrlChanged(String? url) async {
    if (url == null) return;
    // Look for common token param names (loginToken, token, access_token)
    final u = Uri.parse(url);
    final all = <String, String>{}..addAll(u.queryParameters);
    // sometimes token is in fragment
    if (u.fragment.isNotEmpty) {
      try {
        final frag = Uri.splitQueryString(u.fragment);
        all.addAll(frag);
      } catch (_) {}
    }
    String? token = all['loginToken'] ?? all['token'] ?? all['access_token'] ?? all['login_token'];
    if (token == null) {
      // Some synapse setups return 'loginToken' prefixed differently e.g. 'mx_login_token'
      for (final k in all.keys) {
        if (k.toLowerCase().contains('token')) { token = all[k]; break; }
      }
    }
    if (token != null && token.isNotEmpty) {
      // Exchange token for matrix access_token via m.login.token
      try {
        setState(() => _loading = true);
        await _auth.loginWithSsoToken(token);
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('SSO ошибка: $e')));
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _urlSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('SSO — ${widget.idpId}')),
      body: Stack(children: [
        WebViewWidget(controller: _controller),
        if (_loading) const LinearProgressIndicator(minHeight: 3),
      ]),
    );
  }
}
