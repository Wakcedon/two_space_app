import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/services/chat_matrix_service.dart';
import 'package:two_space_app/services/matrix/matrix_auth_service.dart';

/// Specialized service for Matrix media operations
class MatrixMediaService {
  final MatrixAuthService _authService = MatrixAuthService();

  /// Upload bytes to Matrix media repository
  Future<Map<String, dynamic>> uploadBytes(
    List<int> bytes, {
    String? filename,
    String? contentType,
  }) async {
    if (!Environment.useMatrix) {
      throw Exception('Matrix mode not enabled');
    }

    final mxc = await ChatMatrixService().uploadMedia(
      bytes,
      contentType: contentType ?? 'application/octet-stream',
      fileName: filename,
    );

    return {
      '\u0024id': mxc,
      'id': mxc,
      'viewUrl': getFileViewUrl(mxc).toString(),
    };
  }

  /// Upload file to Matrix media repository
  Future<Map<String, dynamic>> uploadFile(
    String filePath, {
    String? filename,
  }) async {
    final bytes = await File(filePath).readAsBytes();
    return await uploadBytes(
      bytes,
      filename: filename ?? File(filePath).uri.pathSegments.last,
    );
  }

  /// Upload file with progress callback
  Future<Map<String, dynamic>> uploadFileWithProgress(
    String filePath, {
    String? filename,
    void Function(int, int)? onProgress,
  }) async {
    final bytes = await File(filePath).readAsBytes();
    final res = await uploadBytes(
      bytes,
      filename: filename ?? File(filePath).uri.pathSegments.last,
    );

    // Report full progress since we don't have streaming upload
    try {
      onProgress?.call(bytes.length, bytes.length);
    } catch (_) {}

    return res;
  }

  /// Get view URL for a media file
  Uri getFileViewUrl(String fileId, {String? bucketId}) {
    // Support Matrix mxc:// URIs
    try {
      if (Environment.useMatrix && fileId.startsWith('mxc://')) {
        final parts = fileId.substring('mxc://'.length).split('/');
        if (parts.length >= 2) {
          final server = parts[0];
          final mediaId = parts.sublist(1).join('/');
          final homeserver = ChatMatrixService().homeserver;
          return Uri.parse(
            '$homeserver/_matrix/media/v3/download/$server/$mediaId',
          );
        }
      }
    } catch (_) {}

    // Fallback to storage bucket URL
    final base = Environment.matrixHomeserverUrl;
    final resolved = (bucketId != null && bucketId.isNotEmpty)
        ? bucketId
        : Environment.matrixStorageMediaBucketId;
    return Uri.parse('$base/storage/buckets/$resolved/files/$fileId/view');
  }

  /// Get file bytes from Matrix media
  Future<Uint8List> getFileBytes(String fileId) async {
    // Handle Matrix mxc:// URIs
    try {
      if (Environment.useMatrix && fileId.startsWith('mxc://')) {
        final parts = fileId.substring('mxc://'.length).split('/');
        if (parts.length >= 2) {
          final server = parts[0];
          final mediaId = parts.sublist(1).join('/');
          final homeserver = ChatMatrixService().homeserver;
          final uri = Uri.parse(
            '$homeserver/_matrix/media/v3/download/$server/$mediaId',
          );

          final token = await _authService.getAccessToken();
          final headers = (token != null && token.isNotEmpty)
              ? {'Authorization': 'Bearer $token'}
              : <String, String>{};

          final res = await http.get(uri, headers: headers);
          if (res.statusCode >= 200 && res.statusCode < 300) {
            return res.bodyBytes;
          }

          throw Exception(
            'Matrix media download failed: ${res.statusCode} ${res.body}',
          );
        }
      }
    } catch (_) {}

    // Fallback: try HTTP GET on view URL
    final uri = getFileViewUrl(fileId);
    final res = await http.get(uri);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.bodyBytes;
    }

    throw Exception('getFileBytes failed: ${res.statusCode} ${res.body}');
  }

  /// Download file to temporary directory
  Future<String> downloadFileToTemp(
    String fileId, {
    String? bucketId,
    String? filename,
  }) async {
    final bytes = await getFileBytes(fileId);
    final tempDir = await getTemporaryDirectory();
    final name = filename ??
        fileId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final fPath = '${tempDir.path}/$name';
    final file = File(fPath);
    await file.writeAsBytes(bytes);
    return fPath;
  }

  /// Delete file (best-effort, may not be supported)
  Future<void> deleteFile(String fileId) async {
    // Matrix content cannot typically be deleted via client
    // This is a no-op unless server provides deletion API
    return;
  }

  /// Get file info/metadata
  Future<Map<String, dynamic>> getFileInfo(
    String fileId, {
    String? bucketId,
  }) async {
    // Minimal metadata for Matrix media
    if (Environment.useMatrix && fileId.startsWith('mxc://')) {
      return {
        '\u0024id': fileId,
        'size': 0,
        'mimeType': 'application/octet-stream',
      };
    }
    throw Exception('getFileInfo not implemented for non-Matrix storage');
  }

  /// Set room avatar from file
  Future<String> setRoomAvatarFromFile(String roomId, String filePath) async {
    if (!Environment.useMatrix) {
      throw Exception('Matrix mode not enabled');
    }

    final bytes = await File(filePath).readAsBytes();
    final mime = 'application/octet-stream';
    return await ChatMatrixService().setRoomAvatar(
      roomId,
      bytes,
      contentType: mime,
      fileName: File(filePath).uri.pathSegments.last,
    );
  }
}
