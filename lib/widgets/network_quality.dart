import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:two_space_app/config/environment.dart';

/// Shows simple network quality indicator (0-3 bars) based on ping RTT to
/// the configured Matrix homeserver. This is a light-weight heuristic and
/// intended for UI feedback only.
class NetworkQualityIndicator extends StatefulWidget {
  const NetworkQualityIndicator({super.key});

  @override
  State<NetworkQualityIndicator> createState() => _NetworkQualityIndicatorState();
}

class _NetworkQualityIndicatorState extends State<NetworkQualityIndicator> {
  Timer? _timer;
  int _bars = 0; // 0..3
  int? _rttMs;

  @override
  void initState() {
    super.initState();
    _check();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final base = Environment.matrixHomeserverUrl;
      if (base.isEmpty) {
        if (mounted) setState(() => _bars = 0);
        return;
      }
      final url = Uri.parse(base.replaceAll(RegExp(r'/$'), '') + '/_matrix/client/versions');
      final sw = Stopwatch()..start();
      final res = await http.get(url).timeout(const Duration(seconds: 3));
      sw.stop();
      final rtt = sw.elapsedMilliseconds;
      int bars = 0;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (rtt < 120) bars = 3;
        else if (rtt < 400) bars = 2;
        else if (rtt < 1200) bars = 1;
        else bars = 0;
      } else {
        bars = 0;
      }
      if (mounted) setState(() {
        _bars = bars;
        _rttMs = rtt;
      });
    } catch (_) {
      if (mounted) setState(() => _bars = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _bars >= 2 ? Colors.greenAccent : (_bars == 1 ? Colors.orangeAccent : Colors.redAccent);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(3, (i) {
          final active = i < _bars;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Container(
              width: 8,
              height: 8 + i * 6,
              decoration: BoxDecoration(
                color: active ? color : Theme.of(context).disabledColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
        if (_rttMs != null) ...[
          const SizedBox(width: 8),
          Text('${_rttMs!} ms', style: TextStyle(color: color, fontSize: 12)),
        ]
      ],
    );
  }
}
