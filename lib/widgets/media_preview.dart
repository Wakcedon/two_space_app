import 'package:flutter/material.dart';
import 'package:two_space_app/services/appwrite_service.dart';

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
  }

  Future<void> _download() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final path = await AppwriteService.downloadFileToTemp(widget.mediaId, filename: widget.filename);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Файл загружен: $path')));
    } catch (e) {
      setState(() {
        _error = AppwriteService.readableError(e);
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
      final temp = await AppwriteService.downloadFileToTemp(widget.mediaId, filename: widget.filename);
      final ok = await AppwriteService.saveFileToGallery(temp);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Сохранено в галерею' : 'Не удалось сохранить')));
    } catch (e) {
      setState(() {
        _error = AppwriteService.readableError(e);
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
      final temp = await AppwriteService.downloadFileToTemp(widget.mediaId, filename: widget.filename);
      final ok = await AppwriteService.shareFile(temp, text: widget.filename);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось открыть лист обмена')));
      }
    } catch (e) {
      setState(() {
        _error = AppwriteService.readableError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewUrl = AppwriteService.getFileViewUrl(widget.mediaId).toString();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Image.network(viewUrl, fit: BoxFit.cover, cacheWidth: 400, cacheHeight: 400, errorBuilder: (c, e, st) => const Center(child: Icon(Icons.broken_image))),
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
