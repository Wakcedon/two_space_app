import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
// import 'package:flutter_webrtc/flutter_webrtc.dart'; // Not configured
import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/services/auth_service.dart';

// Placeholder classes for flutter_webrtc (not configured)
class RTCPeerConnection {
  Function(RTCIceCandidate)? onIceCandidate;
  Function(int?)? onIceConnectionState;
  Function(dynamic)? onTrack;
  
  Future<void> addTrack(dynamic track, [List<MediaStream>? streams]) async {
    throw UnimplementedError('flutter_webrtc not configured');
  }
  
  Future<RTCSessionDescription> createOffer(Map<String, dynamic> offerOptions) async {
    throw UnimplementedError('flutter_webrtc not configured');
  }
  
  Future<RTCSessionDescription> createAnswer(Map<String, dynamic> answerOptions) async {
    throw UnimplementedError('flutter_webrtc not configured');
  }
  
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    throw UnimplementedError('flutter_webrtc not configured');
  }
  
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    throw UnimplementedError('flutter_webrtc not configured');
  }
  
  Future<void> addCandidate(RTCIceCandidate candidate) async {
    throw UnimplementedError('flutter_webrtc not configured');
  }
  
  List<dynamic> getSenders() {
    throw UnimplementedError('flutter_webrtc not configured');
  }
  
  Future<void> close() async {
    throw UnimplementedError('flutter_webrtc not configured');
  }
}
class MediaStream {
  List<dynamic> getTracks() => [];
}
class RTCSessionDescription {
  final String sdp;
  final String type;
  RTCSessionDescription(this.sdp, this.type);
}
class RTCIceCandidate {
  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;
  RTCIceCandidate(this.candidate, this.sdpMid, this.sdpMLineIndex);
}
NavigatorUserMedia? navigator = NavigatorUserMedia();

class NavigatorUserMedia {
  late final MediaDevices mediaDevices;
  NavigatorUserMedia() {
    mediaDevices = MediaDevices();
  }
}

class MediaDevices {
  Future<MediaStream> getUserMedia(Map<String, dynamic> constraints) async {
    throw UnimplementedError('flutter_webrtc not configured');
  }
}

/// Простая реализация signalling поверх Matrix: отправляем/принимаем
/// события типа `io.twospace.call.signal` в комнате. Контент имеет форму:
/// { call_id, action: 'invite'|'answer'|'candidate'|'hangup', sdp?, candidate? }
///
/// Это прагматичный подход: он не претендует быть полной имплементацией
/// спецификации m.call.* но даёт рабочий обмен SDP/ICE для WebRTC.
class CallMatrixService {
  CallMatrixService({String? homeserverUrl}) : homeserver = homeserverUrl ?? Environment.matrixHomeserverUrl;

  final String homeserver;

  String? _since; // token for /sync
  Timer? _syncTimer;

  // Simple in-memory map of callId -> RTCPeerConnection
  final Map<String, RTCPeerConnection> _pcs = {};
  final Map<String, MediaStream> _localStreams = {};

  // Callbacks
  void Function(String callId, Map<String, dynamic> ev)? onInvite;
  void Function(String callId, Map<String, dynamic> ev)? onAnswer;
  void Function(String callId, Map<String, dynamic> ev)? onCandidate;
  void Function(String callId, Map<String, dynamic> ev)? onHangup;
  void Function(String callId, MediaStream stream)? onRemoteStream;
  /// Callback when a local MediaStream is created for a call (preview)
  void Function(String callId, MediaStream stream)? onLocalStream;

  Uri _csPath(String path) => Uri.parse(homeserver + path);

  Future<Map<String, String>> _authHeaders() async {
    String? token;
    try {
      token = await AuthService().getMatrixTokenForUser();
    } catch (_) {
      token = null;
    }
    final tokenString = token ?? Environment.matrixAccessToken;
    final headers = <String, String>{'Content-Type': 'application/json'};
  if (tokenString.isNotEmpty) headers['Authorization'] = 'Bearer $tokenString';
    return headers;
  }

  String _randTxn() => 'c${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1 << 32).toRadixString(36)}';

  Future<void> startSyncLoop({Duration pollInterval = const Duration(milliseconds: 500)}) async {
    // Start a background loop to poll /sync for incoming call signals
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(pollInterval, (_) async {
      try {
        await _doSyncOnce();
      } catch (e) {
        if (kDebugMode) debugPrint('CallMatrixService sync error: $e');
      }
    });
  }

  Future<void> stopSyncLoop() async {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  Future<void> _doSyncOnce() async {
    final qs = (_since != null) ? '?since=${Uri.encodeComponent(_since!)}&timeout=0' : '?timeout=0';
    final uri = _csPath('/_matrix/client/v3/sync$qs');
    final headers = await _authHeaders();
    final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Matrix /sync failed ${res.statusCode}');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    _since = json['next_batch'] as String? ?? _since;

    final rooms = (json['rooms'] as Map?)?['join'] as Map?;
    if (rooms != null) {
      rooms.forEach((roomId, roomObj) {
        try {
          final room = roomObj as Map<String, dynamic>;
          final timeline = (room['timeline'] as Map?)?['events'] as List? ?? [];
            for (final ev in timeline) {
              try {
                final type = ev['type']?.toString() ?? '';
                final content = ev['content'] as Map<String, dynamic>? ?? {};
                // Backwards-compatible custom event
                if (type == 'io.twospace.call.signal') {
                  final callId = content['call_id']?.toString() ?? '';
                  final action = content['action']?.toString() ?? '';
                  if (action == 'invite') {
                    onInvite?.call(callId, {...content, 'room_id': roomId, 'sender': ev['sender']?.toString() ?? ''});
                  } else if (action == 'answer') {
                    onAnswer?.call(callId, {...content, 'room_id': roomId, 'sender': ev['sender']?.toString() ?? ''});
                  } else if (action == 'candidate') {
                    onCandidate?.call(callId, {...content, 'room_id': roomId, 'sender': ev['sender']?.toString() ?? ''});
                  } else if (action == 'hangup') {
                    onHangup?.call(callId, {...content, 'room_id': roomId, 'sender': ev['sender']?.toString() ?? ''});
                  }
                  continue;
                }

                // Handle canonical m.call.* events
                if (type == 'm.call.invite') {
                  final callId = content['call_id']?.toString() ?? '';
                  onInvite?.call(callId, {...content, 'room_id': roomId, 'sender': ev['sender']?.toString() ?? ''});
                  continue;
                }
                if (type == 'm.call.answer') {
                  final callId = content['call_id']?.toString() ?? '';
                  onAnswer?.call(callId, {...content, 'room_id': roomId, 'sender': ev['sender']?.toString() ?? ''});
                  continue;
                }
                if (type == 'm.call.candidates' || type == 'm.call.candidate') {
                  final callId = content['call_id']?.toString() ?? '';
                  onCandidate?.call(callId, {...content, 'room_id': roomId, 'sender': ev['sender']?.toString() ?? ''});
                  continue;
                }
                if (type == 'm.call.hangup') {
                  final callId = content['call_id']?.toString() ?? '';
                  onHangup?.call(callId, {...content, 'room_id': roomId, 'sender': ev['sender']?.toString() ?? ''});
                  continue;
                }
              } catch (_) {}
            }
        } catch (_) {}
      });
    }
  }

  /// Send a room event. By default keeps compatibility with the legacy
  /// `io.twospace.call.signal` type, but callers can specify `eventType`
  /// (e.g. `m.call.invite`, `m.call.answer`, `m.call.candidates`, `m.call.hangup`).
  Future<void> _sendRoomEvent(String roomId, Map<String, dynamic> content, {String eventType = 'io.twospace.call.signal'}) async {
    final txn = _randTxn();
    final uri = _csPath('/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/send/${Uri.encodeComponent(eventType)}/$txn');
    final headers = await _authHeaders();
    final res = await http.put(uri, headers: headers, body: jsonEncode(content)).timeout(const Duration(seconds: 8));
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    if (kDebugMode) debugPrint('sendRoomEvent initial failed ${res.statusCode} for $eventType in $roomId -> ${res.body}');
    // If we are forbidden because the user is not in room, try to join and retry once
    if (res.statusCode == 403) {
      try {
        final body = res.body;
        if (body.contains('not in room') || body.contains('M_FORBIDDEN')) {
          // attempt to join room and retry (use join endpoint that accepts roomId or alias)
          try {
            final joinUri = _csPath('/_matrix/client/v3/join/${Uri.encodeComponent(roomId)}');
            if (kDebugMode) debugPrint('Attempting to join $roomId via $joinUri');
            final joinRes = await http.post(joinUri, headers: headers, body: jsonEncode({})).timeout(const Duration(seconds: 6));
            if (kDebugMode) debugPrint('Join response: ${joinRes.statusCode} ${joinRes.body}');
            if (joinRes.statusCode >= 200 && joinRes.statusCode < 300) {
              final retry = await http.put(uri, headers: headers, body: jsonEncode(content)).timeout(const Duration(seconds: 8));
              if (kDebugMode) debugPrint('Retry send after join: ${retry.statusCode} ${retry.body}');
              if (retry.statusCode >= 200 && retry.statusCode < 300) return;
            }
          } catch (e) {
            if (kDebugMode) debugPrint('Join attempt failed: $e');
          }
        }
      } catch (_) {}
    }
    // If join retry failed, try to create a new private room and invite members from the original room
    if (res.statusCode == 403) {
        try {
          final me = await AuthService().getCurrentUserId();
          if (me != null && me.isNotEmpty) {
            // Attempt to fetch joined members of the original room
            try {
              final jmUri = _csPath('/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/joined_members');
              if (kDebugMode) debugPrint('Fetching joined_members for $roomId -> $jmUri');
              final jmRes = await http.get(jmUri, headers: headers).timeout(const Duration(seconds: 8));
              if (kDebugMode) debugPrint('joined_members response: ${jmRes.statusCode} ${jmRes.body}');
              if (jmRes.statusCode >= 200 && jmRes.statusCode < 300) {
                final jm = jsonDecode(jmRes.body) as Map<String, dynamic>;
                final Map<String, dynamic> joined = jm['joined'] as Map<String, dynamic>? ?? {};
                final invitees = <String>[];
                joined.forEach((uid, _) {
                  if (uid != me) invitees.add(uid);
                });
                if (invitees.isNotEmpty) {
                  // Create a new private room and invite members
                  final createUri = _csPath('/_matrix/client/v3/createRoom');
                  final body = jsonEncode({'preset': 'private_chat', 'invite': invitees});
                  if (kDebugMode) debugPrint('Creating fallback room with invitees: $invitees');
                  final cRes = await http.post(createUri, headers: headers, body: body).timeout(const Duration(seconds: 8));
                  if (kDebugMode) debugPrint('createRoom response: ${cRes.statusCode} ${cRes.body}');
                  if (cRes.statusCode >= 200 && cRes.statusCode < 300) {
                    final created = jsonDecode(cRes.body) as Map<String, dynamic>;
                    final newRoomId = created['room_id'] as String?;
                    if (newRoomId != null && newRoomId.isNotEmpty) {
                      final newUri = _csPath('/_matrix/client/v3/rooms/${Uri.encodeComponent(newRoomId)}/send/${Uri.encodeComponent(eventType)}/$txn');
                      final sendRes = await http.put(newUri, headers: headers, body: jsonEncode(content)).timeout(const Duration(seconds: 8));
                      if (kDebugMode) debugPrint('send to created room: ${sendRes.statusCode} ${sendRes.body}');
                      if (sendRes.statusCode >= 200 && sendRes.statusCode < 300) return;
                    }
                  }
                }
              }
            } catch (_) {}
          }
        } catch (_) {}
      }
    final msg = 'sendRoomEvent failed ${res.statusCode}: ${res.body}';
    if (kDebugMode) debugPrint(msg);
    throw Exception(msg);
  }

  // Placeholder method for createPeerConnection
  Future<RTCPeerConnection> createPeerConnection(Map<String, dynamic> config) async {
    throw UnimplementedError('flutter_webrtc not configured for WebRTC calls');
  }

  Future<String> createCallId() async => 'call-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1<<32).toRadixString(36)}';

  /// Start an outgoing call in the room. Returns callId.
  Future<String> startOutgoingCall(String roomId, {required bool video}) async {
    final callId = await createCallId();
    // Acquire local media
    final mediaConstraints = {
      'audio': true,
      'video': video
          ? {
              'facingMode': 'user',
            }
          : false,
    };
    final localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    // notify UI about local preview stream
    try {
      onLocalStream?.call(callId, localStream);
    } catch (_) {}
    _localStreams[callId] = localStream;

    final iceServers = Environment.turnServers.isNotEmpty ? Environment.turnServers : [ {'urls': 'stun:stun.l.google.com:19302'} ];
    final pc = await createPeerConnection({ 'iceServers': iceServers });

    _pcs[callId] = pc;

    // Add tracks
    localStream.getTracks().forEach((t) => pc.addTrack(t, localStream));

    pc.onIceCandidate = (e) async {
      if (e.candidate == null) return;
      final candidate = {
        'candidate': e.candidate,
        'sdpMid': e.sdpMid,
        'sdpMLineIndex': e.sdpMLineIndex
      };
      final content = {'call_id': callId, 'candidates': [candidate]};
      try {
        await _sendRoomEvent(roomId, content, eventType: 'm.call.candidates');
      } catch (e) {
        if (kDebugMode) debugPrint('Failed to send candidate: $e');
      }
    };

    pc.onIceConnectionState = (state) {
      if (kDebugMode) debugPrint('ICE state: $state');
    };

    pc.onTrack = (event) {
      try {
        if (event.streams.isNotEmpty) {
          final s = event.streams[0];
          onRemoteStream?.call(callId, s);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('onTrack handler error: $e');
      }
    };

    final offer = await pc.createOffer({'offerToReceiveAudio': 1, 'offerToReceiveVideo': video ? 1 : 0});
    await pc.setLocalDescription(offer);

    // Send invite with SDP using canonical m.call.invite
    final content = {
      'call_id': callId,
      'offer': {'type': offer.type, 'sdp': offer.sdp},
      'video': video,
      'version': 0
    };
    await _sendRoomEvent(roomId, content, eventType: 'm.call.invite');
    return callId;
  }

  /// Replace local stream for a running call (useful when switching device)
  Future<void> replaceLocalStream(String callId, MediaStream newStream) async {
    final pc = _pcs[callId];
    if (pc == null) return;
    final old = _localStreams[callId];
    try {
      // Stop old tracks
      old?.getTracks().forEach((t) => t.stop());
    } catch (_) {}
    _localStreams[callId] = newStream;
    // Try to replace senders
    try {
      final senders = await pc.getSenders();
      final tracks = newStream.getTracks();
      int ti = 0;
      for (final s in senders) {
        if (ti < tracks.length) {
          try {
            await s.replaceTrack(tracks[ti]);
          } catch (_) {}
          ti++;
        }
      }
    } catch (_) {}
    try {
      onLocalStream?.call(callId, newStream);
    } catch (_) {}
  }

  // getEstimatedRtt intentionally unimplemented (use NetworkQualityIndicator which measures homeserver RTT)

  Future<void> handleRemoteInvite(String roomId, String callId, String sdp, String type, {required bool video}) async {
    // Create pc and local media, set remote desc, create answer
    final iceServers = Environment.turnServers.isNotEmpty ? Environment.turnServers : [ {'urls': 'stun:stun.l.google.com:19302'} ];
    final pc = await createPeerConnection({ 'iceServers': iceServers });
    _pcs[callId] = pc;

    final localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': video});
    _localStreams[callId] = localStream;
    localStream.getTracks().forEach((t) => pc.addTrack(t, localStream));

    pc.onIceCandidate = (e) async {
      if (e.candidate == null) return;
      final candidate = {
        'candidate': e.candidate,
        'sdpMid': e.sdpMid,
        'sdpMLineIndex': e.sdpMLineIndex
      };
      final content = {'call_id': callId, 'candidates': [candidate]};
      try {
        await _sendRoomEvent(roomId, content, eventType: 'm.call.candidates');
      } catch (e) {
        if (kDebugMode) debugPrint('Failed to send candidate: $e');
      }
    };

    pc.onTrack = (event) {
      try {
        if (event.streams.isNotEmpty) {
          final s = event.streams[0];
          onRemoteStream?.call(callId, s);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('onTrack remote error: $e');
      }
    };

    final remoteDesc = RTCSessionDescription(sdp, type);
    await pc.setRemoteDescription(remoteDesc);
    final answer = await pc.createAnswer({'offerToReceiveVideo': video ? 1 : 0});
    await pc.setLocalDescription(answer);

    // Send answer using canonical m.call.answer
    final content = {
      'call_id': callId,
      'answer': {'type': answer.type, 'sdp': answer.sdp},
      'version': 0
    };
    await _sendRoomEvent(roomId, content, eventType: 'm.call.answer');
  }

  Future<void> handleRemoteAnswer(String roomId, String callId, String sdp, String type) async {
    final pc = _pcs[callId];
    if (pc == null) return;
    final remoteDesc = RTCSessionDescription(sdp, type);
    await pc.setRemoteDescription(remoteDesc);
  }

  Future<void> handleRemoteCandidate(String callId, Map<String, dynamic> candidate) async {
    final pc = _pcs[callId];
    if (pc == null) return;
    try {
      await pc.addCandidate(RTCIceCandidate(candidate['candidate'], candidate['sdpMid'], candidate['sdpMLineIndex']));
    } catch (e) {
      if (kDebugMode) debugPrint('addCandidate failed: $e');
    }
  }

  Future<void> hangup(String roomId, String callId) async {
    final content = {'call_id': callId};
    await _sendRoomEvent(roomId, content, eventType: 'm.call.hangup');
    await _closeCall(callId);
  }

  Future<void> _closeCall(String callId) async {
    final pc = _pcs.remove(callId);
    try {
      await pc?.close();
    } catch (_) {}
    final ls = _localStreams.remove(callId);
    try {
      ls?.getTracks().forEach((t) => t.stop());
    } catch (_) {}
  }
}
