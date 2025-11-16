import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:two_space_app/services/matrix_service.dart';
import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/services/auth_service.dart';
import 'package:two_space_app/services/chat_matrix_service.dart';

/// Simple media preview widget used in chat messages and galleries.
class MediaPreview extends StatefulWidget {
  final String mediaId;
  final String? filename;
  final String? mimeType; // optional mime type passed from callers
  final double? maxHeight;
  final bool autoDownload;

  const MediaPreview({super.key, required this.mediaId, this.filename, this.mimeType, this.maxHeight, this.autoDownload = false});

  @override
  State<MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<MediaPreview> {
  bool _loading = false;
  String? _error;
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    if (widget.autoDownload) {
      // trigger a background download (ignore errors, show a tiny progress)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _download();
        }
      });
    }
    // If this is Matrix media (mxc://) and Matrix is enabled, prefetch bytes
    if (Environment.useMatrix && widget.mediaId.startsWith('mxc://')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchMatrixMedia();
      });
    }
  }

  Future<void> _fetchMatrixMedia() async {
    try {
      setState(() => _loading = true);
      final parts = widget.mediaId.substring('mxc://'.length).split('/');
      if (parts.length < 2) return;
      final server = parts[0];
      final mediaId = parts.sublist(1).join('/');
      final homeserver = ChatMatrixService().homeserver;
      final uri = Uri.parse(homeserver + '/_matrix/media/v3/download/$server/$mediaId');
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
        if (mounted) setState(() => _bytes = Uint8List.fromList(res.bodyBytes));
      } else {
        if (mounted) setState(() => _error = 'Matrix media fetch failed: ${res.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (Environment.useMatrix && widget.mediaId.startsWith('mxc://')) {
        // Matrix media: fetch bytes and write to temp
        if (_bytes == null) await _fetchMatrixMedia();
        if (_bytes == null) throw Exception('No data');
        final tmp = await _writeBytesToTemp(_bytes!, widget.filename);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Файл загружен: $tmp')));
      } else {
        final path = await MatrixService.downloadFileToTemp(widget.mediaId, filename: widget.filename);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Файл загружен: $path')));
      }
    } catch (e) {
      setState(() {
        _error = Environment.useMatrix && widget.mediaId.startsWith('mxc://') ? e.toString() : MatrixService.readableError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveToGallery() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (Environment.useMatrix && widget.mediaId.startsWith('mxc://')) {
        if (_bytes == null) await _fetchMatrixMedia();
        if (_bytes == null) throw Exception('No data');
        final tmp = await _writeBytesToTemp(_bytes!, widget.filename);
        // Saving to gallery isn't implemented for generic matrix media here.
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Файл сохранён временно: $tmp')));
      } else {
        final temp = await MatrixService.downloadFileToTemp(widget.mediaId, filename: widget.filename);
        final ok = await MatrixService.saveFileToGallery(temp);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Сохранено в галерею' : 'Не удалось сохранить')));
      }
    } catch (e) {
      setState(() {
        _error = Environment.useMatrix && widget.mediaId.startsWith('mxc://') ? e.toString() : MatrixService.readableError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _share() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (Environment.useMatrix && widget.mediaId.startsWith('mxc://')) {
        if (_bytes == null) await _fetchMatrixMedia();
        if (_bytes == null) throw Exception('No data');
        final tmp = await _writeBytesToTemp(_bytes!, widget.filename);
        // Sharing implementation for Matrix media: reuse MatrixService.shareFile if available for file path
        final ok = await MatrixService.shareFile(tmp, text: widget.filename);
        if (!mounted) return;
        if (!ok) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось открыть лист обмена')));
      } else {
        final temp = await MatrixService.downloadFileToTemp(widget.mediaId, filename: widget.filename);
        final ok = await MatrixService.shareFile(temp, text: widget.filename);
        if (!mounted) return;
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось открыть лист обмена')));
        }
      }
    } catch (e) {
      setState(() {
        _error = Environment.useMatrix && widget.mediaId.startsWith('mxc://') ? e.toString() : MatrixService.readableError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<String> _writeBytesToTemp(Uint8List bytes, String? filename) async {
    final dir = await getTemporaryDirectory();
    final name = filename != null && filename.isNotEmpty ? filename : 'matrix_media_${DateTime.now().millisecondsSinceEpoch}';
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  @override
  Widget build(BuildContext context) {
    final viewUrl = MatrixService.getFileViewUrl(widget.mediaId).toString();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Builder(builder: (c) {
            if (Environment.useMatrix && widget.mediaId.startsWith('mxc://')) {
              if (_bytes != null) return Image.memory(_bytes!, fit: BoxFit.cover);
              if (_error != null) return Center(child: Text('Ошибка: $_error'));
              return const Center(child: CircularProgressIndicator());
            }
            return Image.network(viewUrl, fit: BoxFit.cover, errorBuilder: (c, e, st) => const Center(child: Icon(Icons.broken_image)));
          }),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Ошибка: $_error', style: const TextStyle(color: Colors.red))),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          IconButton(onPressed: _loading ? null : _download, icon: const Icon(Icons.download)),
          IconButton(onPressed: _loading ? null : _saveToGallery, icon: const Icon(Icons.save_alt)),
          IconButton(onPressed: _loading ? null : _share, icon: const Icon(Icons.share)),
        ])
      ],
    );
  }
}
