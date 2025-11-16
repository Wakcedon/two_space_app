import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/services/auth_service.dart';
import 'package:two_space_app/services/chat_matrix_service.dart';
import 'package:two_space_app/services/appwrite_service.dart';

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

  Future<void> _loadIfNeeded() async {
    String? fid = widget.avatarFileId;
    // If avatarFileId not provided, try to extract file id from avatarUrl if it contains /files/{id}
    if (fid == null || fid.isEmpty) {
      final url = widget.avatarUrl;
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
    if (_cache.containsKey(fid)) {
      setState(() => _bytes = _cache[fid]);
      return;
    }
    try {
      final b = await AppwriteService.getFileBytes(fid);
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
      return CircleAvatar(radius: r, backgroundImage: NetworkImage(widget.avatarUrl!), backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: widget.initials == null ? null : Text(widget.initials ?? ''));
    }

    // If no avatar available, but we have fullName and Appwrite configured, use Appwrite's avatars initials endpoint
    if ((widget.fullName != null && widget.fullName!.isNotEmpty) && Environment.appwritePublicEndpoint.isNotEmpty && Environment.appwriteProjectId.isNotEmpty) {
      try {
  var ep = Environment.appwritePublicEndpoint.trim();
  // Trim trailing slashes safely
  ep = ep.replaceAll(RegExp(r'/+$'), '');
  if (!ep.endsWith('/v1')) ep = '$ep/v1';
        final url = Uri.parse('$ep/avatars/initials?name=${Uri.encodeComponent(widget.fullName!)}');
        return CircleAvatar(radius: r, backgroundImage: NetworkImage(url.toString()), backgroundColor: Theme.of(context).colorScheme.primaryContainer);
      } catch (_) {}
    }

    // Fallback: display local initials text
    return CircleAvatar(radius: r, backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: Text(widget.initials ?? '?'));
  }
}
