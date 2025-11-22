import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/services/auth_service.dart';
import 'package:two_space_app/services/chat_matrix_service.dart';
import 'package:two_space_app/services/matrix_service.dart';

/// Reusable user avatar widget.
/// Prefer avatarFileId (fetch bytes via AppwriteService.getFileBytes).
/// Fallback to avatarUrl (NetworkImage) or initials.
class UserAvatar extends StatefulWidget {
  final String? avatarUrl;
  final String? avatarFileId;
  final String? initials;
  final String? fullName;
  final double radius;

  const UserAvatar({super.key, this.avatarUrl, this.avatarFileId, this.initials, this.fullName, this.radius = 24});

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  Uint8List? _bytes;
  static final Map<String, Uint8List> _cache = {};

  @override
  void initState() {
    super.initState();
    _loadIfNeeded();
  }

  @override
  void didUpdateWidget(covariant UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If avatar data changed, clear cached bytes and reload
    if (oldWidget.avatarFileId != widget.avatarFileId || oldWidget.avatarUrl != widget.avatarUrl) {
      if (widget.avatarFileId != null && widget.avatarFileId!.isNotEmpty) {
        _cache.remove(widget.avatarFileId);
      }
      _bytes = null;
      _loadIfNeeded();
    }
  }

  Future<void> _loadIfNeeded() async {
    String? fid = widget.avatarFileId;
    // Avatar URL (if any)
    final String? url = widget.avatarUrl;
    // If avatarFileId not provided, try to extract file id from avatarUrl if it contains /files/{id}
    if (fid == null || fid.isEmpty) {
      if (url != null && url.isNotEmpty) {
        try {
          final uri = Uri.parse(url);
          final segments = uri.pathSegments;
          // find 'files' segment and take next segment as id
          final idx = segments.indexOf('files');
          if (idx >= 0 && idx + 1 < segments.length) {
            fid = segments[idx + 1];
          }
        } catch (_) {}
      }
    }
    // If url looks like a Matrix media download path, try authenticated fetch
    if ((fid == null || fid.isEmpty) && Environment.useMatrix && url != null && url.contains('/_matrix/media/v3/download')) {
      try {
        final uri = Uri.parse(url);
        String? token;
        try { token = await AuthService().getMatrixTokenForUser(); } catch (_) { token = null; }
        String tokenString = '';
        if (token != null && token.isNotEmpty) tokenString = token;
        else if (Environment.matrixAccessToken.isNotEmpty) tokenString = Environment.matrixAccessToken;
        final headers = tokenString.isNotEmpty ? {'Authorization': 'Bearer $tokenString'} : <String, String>{};
        final res = await http.get(uri, headers: headers);
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          final u = Uint8List.fromList(res.bodyBytes);
          if (mounted) setState(() => _bytes = u);
          return;
        }
      } catch (_) {}
    }
    if (fid == null || fid.isEmpty) {
      // If using Matrix and avatarUrl is an mxc:// URL, try to fetch it from
      // the homeserver content repo using the authenticated download endpoint.
      if (Environment.useMatrix && widget.avatarUrl != null && widget.avatarUrl!.startsWith('mxc://')) {
        try {
          final parts = widget.avatarUrl!.substring('mxc://'.length).split('/');
          if (parts.length >= 2) {
            final server = parts[0];
            final mediaId = parts.sublist(1).join('/');
            final homeserver = ChatMatrixService().homeserver;
            final uri = Uri.parse(homeserver + '/_matrix/media/v3/download/$server/$mediaId');
            // Get auth header (per-user or global)
            String? token;
            try {
              token = await AuthService().getMatrixTokenForUser();
            } catch (_) {
              token = null;
            }
            String tokenString = '';
            if (token != null && token.isNotEmpty) tokenString = token;
            else if (Environment.matrixAccessToken.isNotEmpty) tokenString = Environment.matrixAccessToken;
            final headers = tokenString.isNotEmpty ? {'Authorization': 'Bearer $tokenString'} : <String, String>{};
            final res = await http.get(uri, headers: headers);
            if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
              final u = Uint8List.fromList(res.bodyBytes);
              if (mounted) setState(() => _bytes = u);
              return;
            }
          }
        } catch (_) {}
      }
      return;
    }
  if (fid.isNotEmpty && _cache.containsKey(fid)) {
      setState(() => _bytes = _cache[fid]);
      return;
    }
    try {
      final b = await MatrixService.getFileBytes(fid);
      if (b.isNotEmpty) {
        final u = Uint8List.fromList(b);
        _cache[fid] = u;
        if (mounted) setState(() => _bytes = u);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.radius;
    if (_bytes != null) {
      return CircleAvatar(radius: r, backgroundColor: Colors.transparent, child: ClipOval(child: Image.memory(_bytes!, width: r * 2, height: r * 2, fit: BoxFit.cover)));
    }
    if (widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        key: ValueKey(widget.avatarUrl),
        radius: r,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        backgroundImage: NetworkImage(widget.avatarUrl!),
        onBackgroundImageError: (exception, stackTrace) {
          // Fallback on network image load error
        },
        child: widget.initials == null ? null : Text(widget.initials ?? ''),
      );
    }

    // Fallback: display local initials text (no Appwrite dependency)
    return CircleAvatar(radius: r, backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: Text(widget.initials ?? '?'));
  }
}
