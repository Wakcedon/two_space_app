import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/services/chat_backend_factory.dart';
import 'package:two_space_app/services/chat_backend.dart';
import 'package:two_space_app/services/call_matrix_service.dart';
import 'package:two_space_app/widgets/network_quality.dart';

class CallScreen extends StatefulWidget {
  final String room;
  final bool isVideo;
  final String? subject;
  final String? avatarUrl;
  final String? displayName;

  const CallScreen({super.key, required this.room, this.isVideo = true, this.subject, this.avatarUrl, this.displayName});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _audioMuted = false;
  bool _videoMuted = false;
  bool _inCall = false;
  bool _remoteVisible = false;
  bool _localVisible = false;
  ChatBackend? _chatBackend;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  late final CallMatrixService _callService;
  String? _currentCallId;
  static const _animDur = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    _chatBackend = createChatBackend();
    _initRenderers();
    _callService = CallMatrixService();
    _callService.onInvite = _onInviteReceived;
    _callService.onAnswer = _onAnswerReceived;
    _callService.onLocalStream = (callId, stream) {
      if (mounted) {
        _localRenderer.srcObject = stream;
        setState(() => _localVisible = true);
      }
    };
    _callService.onCandidate = (callId, ev) async {
      try {
        Map<String, dynamic>? cand;
        if (ev['candidate'] is Map<String, dynamic>) cand = ev['candidate'] as Map<String, dynamic>;
        else if (ev['candidates'] is List && (ev['candidates'] as List).isNotEmpty) cand = (ev['candidates'] as List).first as Map<String, dynamic>?;
        if (cand != null) await _callService.handleRemoteCandidate(callId, cand);
      } catch (e) {}
    };
    _callService.onHangup = (callId, ev) {
      if (mounted) {
        setState(() => _inCall = false);
      }
    };
    _callService.onRemoteStream = (callId, stream) {
      if (mounted) {
        _remoteRenderer.srcObject = stream;
        setState(() => _remoteVisible = true);
      }
    };
    _callService.startSyncLoop();
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _callService.stopSyncLoop();
    super.dispose();
  }

  void _onInviteReceived(String callId, Map<String, dynamic> ev) async {
    // Incoming call — show accept dialog
    if (!mounted) return;
    final video = ev['video'] == true;
    final from = ev['sender'] ?? ev['from'] ?? '';
    final accept = await showDialog<bool>(context: context, builder: (c) {
      return AlertDialog(
        title: const Text('Входящий звонок'),
        content: Text('Входящий ${video ? 'видео' : 'аудио'} звонок от $from'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Отклонить')),
          TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Принять')),
        ],
      );
    });
    if (accept == true) {
      setState(() => _inCall = true);
      _currentCallId = callId;
      // handleRemoteInvite will create PC, local stream and send answer
      final roomId = ev['room_id']?.toString() ?? widget.room;
      // Support both legacy payloads and m.call.invite (which has 'offer')
      String sdp = '';
      String type = 'offer';
      if (ev['offer'] is Map) {
        final off = ev['offer'] as Map<String, dynamic>;
        sdp = off['sdp']?.toString() ?? '';
        type = off['type']?.toString() ?? 'offer';
      } else {
        sdp = ev['sdp']?.toString() ?? '';
        type = ev['type']?.toString() ?? 'offer';
      }
      await _callService.handleRemoteInvite(roomId, callId, sdp, type, video: video);
    }
  }

  void _onAnswerReceived(String callId, Map<String, dynamic> ev) async {
    // Remote answered our offer
    try {
      // support m.call.answer shape with 'answer' object
      String sdp = '';
      String type = 'answer';
      if (ev['answer'] is Map) {
        final ans = ev['answer'] as Map<String, dynamic>;
        sdp = ans['sdp']?.toString() ?? '';
        type = ans['type']?.toString() ?? 'answer';
      } else {
        sdp = ev['sdp']?.toString() ?? '';
        type = ev['type']?.toString() ?? 'answer';
      }
      await _callService.handleRemoteAnswer(ev['room_id']?.toString() ?? widget.room, callId, sdp, type);
      if (mounted) setState(() => _inCall = true);
    } catch (e) {}
  }

  Future<void> _joinMeeting() async {
    // Start native WebRTC call via signalling
    try {
      final ok = await _ensurePermissions();
      if (!ok) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Необходимо разрешение на микрофон и камеру')));
        return;
      }
      final roomId = widget.room;
      final callId = await _callService.startOutgoingCall(roomId, video: widget.isVideo);
      _currentCallId = callId;
      if (mounted) setState(() => _inCall = true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось начать звонок: $e')));
    }
  }

  /// Request microphone and camera permissions where relevant (mobile).
  Future<bool> _ensurePermissions() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final mic = await Permission.microphone.status;
        final cam = await Permission.camera.status;
        if (mic.isGranted && (widget.isVideo == false || cam.isGranted)) return true;

        final results = await [Permission.microphone, Permission.camera].request();
        final micOk = results[Permission.microphone]?.isGranted == true;
        final camOk = widget.isVideo ? (results[Permission.camera]?.isGranted == true) : true;
        return micOk && camOk;
      }
      // On other platforms assume permissions are available (desktop handled via browser/webview)
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _inviteUser() async {
    final picked = await showDialog<String?>(context: context, builder: (c) {
      final ctrl = TextEditingController();
      return AlertDialog(
        title: const Text('Пригласить в звонок'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'User id или никнейм')),
        actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Отмена')), TextButton(onPressed: () => Navigator.of(c).pop(ctrl.text.trim()), child: const Text('Пригласить'))],
      );
    });
    if (picked == null || picked.isEmpty) return;
    try {
      // Try to create/get direct chat and send meeting link
      final cs = _chatBackend ?? createChatBackend();
      final chatDoc = await cs.getOrCreateDirectChat(picked);
      final chatId = (chatDoc['\$id'] ?? chatDoc['id'] ?? '').toString();
      final link = '${Environment.matrixHomeserverUrl.replaceAll(RegExp(r'/$'), '')}/${widget.room}';
      await cs.sendMessage(chatId, '', 'Приглашаю на звонок: $link', type: 'call_invite');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Приглашение отправлено')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка приглашения: $e')));
    }
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(fit: StackFit.expand, children: [
        // blurred background
        BackdropFilter(filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0), child: Container(color: Colors.black.withOpacity(0.35))),
        SafeArea(
          child: Center(
            child: LayoutBuilder(builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final contentWidth = maxW > 1000 ? 900.0 : (maxW * 0.95);
              final isWide = maxW > 700;
              return ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentWidth),
                child: AnimatedContainer(
                  duration: _animDur,
                  margin: const EdgeInsets.symmetric(vertical: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.06))),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    // Video / avatar area
                    SizedBox(
                      height: isWide ? 420 : 260,
                      child: Stack(children: [
                        // remote or placeholder
                        Positioned.fill(
                          child: AnimatedSwitcher(
                            duration: _animDur,
                            child: _remoteVisible && widget.isVideo
                                ? Container(key: const ValueKey('remote'), color: Colors.black, child: RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain))
                                : Container(key: const ValueKey('placeholder'), color: Colors.black87, alignment: Alignment.center, child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.person, size: isWide ? 72 : 48, color: Colors.white24), const SizedBox(height: 8), Text(widget.displayName ?? widget.room, style: TextStyle(color: Colors.white54, fontSize: isWide ? 22 : 16))])),
                          ),
                        ),

                        // local preview overlay (small)
                        Positioned(
                          right: 14,
                          top: 14,
                          child: AnimatedOpacity(
                            opacity: _localVisible ? 1 : 0,
                            duration: _animDur,
                            child: Container(
                              width: isWide ? 260 : 120,
                              height: isWide ? 160 : 96,
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.black54, boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 8)]),
                              child: ClipRRect(borderRadius: BorderRadius.circular(12), child: RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)),
                            ),
                          ),
                        ),
                      ]),
                    ),

                    const SizedBox(height: 12),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                        Text(widget.displayName ?? widget.room, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(_inCall ? 'В разговоре' : (widget.isVideo ? 'Видео-звонок' : 'Аудио-звонок'), style: const TextStyle(color: Colors.white70)),
                      ])),
                      // small quality indicator
                      Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)), child: const NetworkQualityIndicator())
                    ]),

                    const SizedBox(height: 12),

                    // controls row
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      _buildControl(Icons.mic, _audioMuted ? 'Микрофон выкл' : 'Микрофон', _audioMuted, () async {
                        setState(() => _audioMuted = !_audioMuted);
                      }),
                      const SizedBox(width: 18),
                      _buildControl(Icons.videocam, _videoMuted ? 'Камера выкл' : 'Камера', _videoMuted, () async {
                        setState(() => _videoMuted = !_videoMuted);
                      }),
                      const SizedBox(width: 12),
                      InkWell(onTap: _showDevicePicker, borderRadius: BorderRadius.circular(20), child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white12, shape: BoxShape.circle), child: const Icon(Icons.devices, color: Colors.white, size: 20))),
                    ]),

                    const SizedBox(height: 16),

                    // action buttons
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      ElevatedButton.icon(
                        onPressed: _inviteUser,
                        icon: const Icon(Icons.person_add),
                        label: const Text('Пригласить'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.white24, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      ),
                      const SizedBox(width: 18),

                      // central call button with scale animation
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 1.0, end: _inCall ? 0.92 : 1.0),
                        duration: const Duration(milliseconds: 220),
                        builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                        child: ElevatedButton(
                          onPressed: () async {
                            await _joinMeeting();
                          },
                          style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)), backgroundColor: Colors.greenAccent, fixedSize: const Size(84, 84)),
                          child: Icon(_inCall ? Icons.phone_in_talk : Icons.phone, color: Colors.white, size: 36),
                        ),
                      ),
                      const SizedBox(width: 18),

                      ElevatedButton(
                        onPressed: () async {
                          try {
                            if (_currentCallId != null) await _callService.hangup(widget.room, _currentCallId!);
                          } catch (_) {}
                          if (mounted) Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), backgroundColor: Colors.redAccent, fixedSize: const Size(64, 64)),
                        child: const Icon(Icons.call_end, color: Colors.white),
                      ),
                    ]),
                  ]),
                ),
              );
            }),
          ),
        ),
      ]),
    );
  }

  Widget _buildControl(IconData icon, String label, bool active, VoidCallback onTap) {
    return Column(children: [
      InkWell(onTap: onTap, borderRadius: BorderRadius.circular(24), child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: active ? Colors.white24 : Colors.white12, shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: 26))),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))
    ]);
  }

  Future<void> _showDevicePicker() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      final audioInputs = devices.where((d) => d.kind == 'audioinput').toList();
      final videoInputs = devices.where((d) => d.kind == 'videoinput').toList();
      final picked = await showDialog<Map<String, String?>>(context: context, builder: (c) {
        String? selAudio;
        String? selVideo;
        return AlertDialog(
          title: const Text('Выбор устройств'),
          content: StatefulBuilder(builder: (st, setSt) {
            return Column(mainAxisSize: MainAxisSize.min, children: [
              if (audioInputs.isNotEmpty) ...[
                const Text('Микрофон'),
                DropdownButton<String>(value: selAudio, isExpanded: true, hint: const Text('Выберите микрофон'), items: audioInputs.map((d) => DropdownMenuItem(value: d.deviceId, child: Text(d.label))).toList(), onChanged: (v) => setSt(() => selAudio = v)),
              ],
              if (videoInputs.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Камера'),
                DropdownButton<String>(value: selVideo, isExpanded: true, hint: const Text('Выберите камеру'), items: videoInputs.map((d) => DropdownMenuItem(value: d.deviceId, child: Text(d.label))).toList(), onChanged: (v) => setSt(() => selVideo = v)),
              ],
            ]);
          }),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Отмена')),
            TextButton(onPressed: () => Navigator.of(c).pop({'audio': selAudio, 'video': selVideo}), child: const Text('Выбрать')),
          ],
        );
      });
      if (picked == null) return;
      // acquire new local stream with selected device ids
      final constraints = {
        'audio': picked['audio'] != null ? {'deviceId': {'exact': picked['audio']}} : true,
        'video': picked['video'] != null ? {'deviceId': {'exact': picked['video']}} : (widget.isVideo ? true : false),
      };
      final newStream = await navigator.mediaDevices.getUserMedia(constraints);
      if (_currentCallId != null) {
        await _callService.replaceLocalStream(_currentCallId!, newStream);
      } else {
        // just preview
        _localRenderer.srcObject = newStream;
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось выбрать устройство: $e')));
    }
  }
}

class _JaaSEmbedPage extends StatefulWidget {
  final String room;
  final String jwt;
  final String server;
  const _JaaSEmbedPage({required this.room, required this.jwt, required this.server});

  @override
  State<_JaaSEmbedPage> createState() => _JaaSEmbedPageState();
}

class _JaaSEmbedPageState extends State<_JaaSEmbedPage> {
  late final WebViewController _controller;

  String _buildHtml(String server, String room, String jwt) {
    final base = server.isNotEmpty ? server.replaceAll(RegExp(r'/$'), '') : 'https://8x8.vc';
    final scriptUrl = '$base/vpaas-magic-cookie-14196d2622f147788888c34f8a21a882/external_api.js';
    final sanitizedRoom = room.replaceAll('"', '');
    final sanitizedJwt = jwt.replaceAll('"', '');
    return '''
<!doctype html>
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <script src="$scriptUrl"></script>
    <style>html,body,#jaas-container{height:100%;margin:0;padding:0}#controls{position:fixed;left:8px;top:8px;z-index:1000;background:rgba(0,0,0,0.6);color:#fff;padding:8px;border-radius:8px}</style>
    <script>
      let api = null;
      async function startCall(){
        const roomName = "$sanitizedRoom";
        const parent = document.querySelector('#jaas-container');
        const options = {roomName: roomName, parentNode: parent, configOverwrite: {startWithVideoMuted: false, startWithAudioMuted:false}};
        if ("$sanitizedJwt".length>0) options.jwt = "$sanitizedJwt";
        api = new JitsiMeetExternalAPI("8x8.vc", options);
        api.addEventListener('videoConferenceJoined', () => {console.log('joined')});
      }
      function enumerate(){
        if (!navigator.mediaDevices || !navigator.mediaDevices.enumerateDevices) return;
        navigator.mediaDevices.enumerateDevices().then(devs=>{
          const selAudio = document.getElementById('audio');
          const selVideo = document.getElementById('video');
          selAudio.innerHTML=''; selVideo.innerHTML='';
          devs.forEach(d=>{
            const opt = document.createElement('option'); opt.value=d.deviceId; opt.text=d.kind+': '+(d.label||d.deviceId);
            if (d.kind==='audioinput') selAudio.appendChild(opt);
            if (d.kind==='videoinput') selVideo.appendChild(opt);
          });
        }).catch(e=>console.warn('enum',e));
      }
      window.addEventListener('load', ()=>{enumerate();});
    </script>
  </head>
  <body>
    <div id="controls">
      <div>Device selection (используйте для Desktop):</div>
      <div>
        <label>Микрофон: <select id="audio"></select></label>
      </div>
      <div>
        <label>Камера: <select id="video"></select></label>
      </div>
      <div style="margin-top:6px"><button onclick="startCall()">Start call</button></div>
    </div>
    <div id="jaas-container"></div>
  </body>
</html>
''';
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted);
    final html = _buildHtml(widget.server, widget.room, widget.jwt);
    _controller.loadHtmlString(html);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Встроенный звонок')),
      body: WebViewWidget(controller: _controller),
    );
  }
}
