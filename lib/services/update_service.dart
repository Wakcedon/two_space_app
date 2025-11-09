import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../services/appwrite_service.dart';
import '../screens/update_screen.dart';
import '../config/environment.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

class UpdateInfo {
  final String latestVersion;
  final String updateUrl; // direct URL to APK
  final String? apkFileId; // AppWrite file id
  final String? apkBucketId; // optional bucket id
  final String notes;
  final String? sha256;
  final String? platform;
  final bool forceUpdate;
  final String? selectedAbi;

  UpdateInfo({required this.latestVersion, required this.updateUrl, this.notes = '', this.apkFileId, this.apkBucketId, this.sha256, this.platform, this.forceUpdate = false, this.selectedAbi});

  factory UpdateInfo.fromJson(Map<String, dynamic> j) => UpdateInfo(
        latestVersion: j['version']?.toString() ?? '',
        updateUrl: j['apkURL']?.toString() ?? j['apkUrl']?.toString() ?? '',
        apkFileId: j['apkFileId']?.toString(),
        apkBucketId: j['apkBucketId']?.toString(),
        notes: j['notes']?.toString() ?? '',
        sha256: j['sha256']?.toString(),
        platform: j['platform']?.toString(),
        forceUpdate: (j['forceUpdate'] == true) || (j['forceUpdate']?.toString().toLowerCase() == 'true'),
        selectedAbi: j['selectedAbi']?.toString(),
      );
}

Future<String> _detectDeviceAbi() async {
  try {
    final dip = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final and = await dip.androidInfo;
      final abis = and.supportedAbis;
      if (abis.isNotEmpty) return abis.first;
      // Try cpuAbi fields as fallback (older SDKs)
      final abi32 = and.supported32BitAbis;
      if (abi32.isNotEmpty) return abi32.first;
      return '';
    } else if (Platform.isIOS) {
      final ios = await dip.iosInfo;
      return ios.utsname.machine;
    }
  } catch (_) {}
  return '';
}

class UpdateService {
  static const MethodChannel _channel = MethodChannel('two_space_app/update');

  static Future<bool> canRequestInstallPackages() async {
    try {
      final res = await _channel.invokeMethod<bool>('canRequestInstallPackages');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openInstallSettings() async {
    try {
      final res = await _channel.invokeMethod<bool>('openInstallSettings');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  // Returns UpdateInfo if available and newer than current app, otherwise null
  static Future<UpdateInfo?> checkForUpdate() async {
    // If Appwrite is configured and an updates collection id is provided, prefer fetching the latest update document from Appwrite.
    try {
      if (kDebugMode) debugPrint('UpdateService: starting checkForUpdate');
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;
      final currentBuild = info.buildNumber;
      if (kDebugMode) debugPrint('UpdateService: current version=$currentVersion build=$currentBuild');

      final coll = Environment.appwriteUpdatesCollectionId;
      if (AppwriteService.isConfigured && coll.isNotEmpty) {
        final base = AppwriteService.v1Endpoint();
        // Fetch up to 20 recent documents (newest first)
  final seg = Environment.appwriteCollectionsSegment;
  final docSeg = Environment.appwriteDocumentsSegment;
  final uri = Uri.parse('$base/databases/${Environment.appwriteDatabaseId}/$seg/$coll/$docSeg?limit=20&orderField=%24createdAt&orderType=DESC');
        final headers = <String, String>{'x-appwrite-project': Environment.appwriteProjectId};
        if (Environment.appwriteApiKey.isNotEmpty) headers['x-appwrite-key'] = Environment.appwriteApiKey;
        final cookie = await AppwriteService.getSessionCookie();
        if (cookie != null && cookie.isNotEmpty) headers['cookie'] = cookie;

        if (kDebugMode) debugPrint('UpdateService: fetching updates from $uri');
        final resp = await http.get(uri, headers: headers);
        if (resp.statusCode != 200) {
          if (kDebugMode) debugPrint('UpdateService: update fetch failed status=${resp.statusCode}');
          return null;
        }

        final Map<String, dynamic> body = jsonDecode(resp.body) as Map<String, dynamic>;
        final docs = (body['documents'] as List<dynamic>?) ?? [];
        if (docs.isEmpty) return null;

        final deviceCore = await _detectDeviceAbi();
        if (kDebugMode) debugPrint('UpdateService: deviceCore=$deviceCore');

        for (final raw in docs) {
          try {
            final Map<String, dynamic> doc = Map<String, dynamic>.from(raw as Map);
            final docPlatform = (doc['platform'] ?? '').toString();
            if (docPlatform.isNotEmpty && docPlatform != 'android') {
              continue; // skip non-android documents
            }

            final docCore = (doc['core'] ?? doc['coreName'] ?? '').toString();
            // If docCore is specified, it must match deviceCore, or be a wildcard 'any'/'default'
            if (docCore.isNotEmpty && deviceCore.isNotEmpty && docCore != deviceCore && docCore != 'any' && docCore != 'default') {
              continue;
            }

            final version = (doc['version'] ?? '').toString();
            final notes = (doc['notes'] ?? '').toString();
            final apkFileId = (doc['apkFileId'] ?? '').toString();
            final apkBucketId = (doc['apkBucketId'] ?? '').toString();
            final sha = (doc['sha256'] ?? '').toString();
            final force = (doc['forceUpdate'] == true) || (doc['forceUpdate']?.toString().toLowerCase() == 'true');

            String apkUrl = (doc['apkURL'] ?? doc['apkUrl'] ?? '').toString();
            if (apkUrl.isEmpty && apkFileId.isNotEmpty) {
              try {
                final chosenBucket = (apkBucketId.isNotEmpty) ? apkBucketId : (Environment.appwriteStorageApkBucketId.isNotEmpty ? Environment.appwriteStorageApkBucketId : null);
                final u = AppwriteService.getFileViewUrl(apkFileId, bucketId: chosenBucket);
                apkUrl = u.toString();
              } catch (e) {
                if (kDebugMode) debugPrint('Failed to build file view url: $e');
              }
            }

            final update = UpdateInfo(
              latestVersion: version,
              updateUrl: apkUrl,
              notes: notes,
              apkFileId: apkFileId.isNotEmpty ? apkFileId : null,
              apkBucketId: apkBucketId.isNotEmpty ? apkBucketId : null,
              sha256: sha.isNotEmpty ? sha : null,
              platform: 'android',
              forceUpdate: force,
              selectedAbi: docCore.isNotEmpty ? docCore : null,
            );

            // If document contains a build number and it's greater than current - treat as update
            try {
              final docBuild = (doc['build'] ?? doc['buildNumber'])?.toString();
              if (docBuild != null && docBuild.isNotEmpty) {
                final di = int.tryParse(docBuild);
                final ci = int.tryParse(currentBuild);
                if (di != null && ci != null && di > ci) {
                  if (kDebugMode) debugPrint('Update available by build: $di > $ci');
                  return update;
                }
              }
            } catch (_) {}

            // Otherwise, compare semantic versions
            if (_isNewer(update.latestVersion, currentVersion)) {
              if (kDebugMode) debugPrint('Update available: ${update.latestVersion} > $currentVersion selectedCore=${update.selectedAbi} url=${update.updateUrl}');
              return update;
            }
          } catch (e) {
            if (kDebugMode) debugPrint('Skipping malformed update doc: $e');
            continue;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Update check failed: $e');
    }
    return null;
  }

  // downloads apk to temp file and returns local path
  static Future<String?> downloadApk(String url, {ValueChanged<double>? onProgress}) async {
    try {
      final client = http.Client();
      final uri = Uri.parse(url);
      final req = http.Request('GET', uri);

      // If URL is served by Appwrite, include project header and optional api key / cookie
      try {
        final base = AppwriteService.v1Endpoint();
        if (uri.toString().startsWith(base)) {
          req.headers['x-appwrite-project'] = Environment.appwriteProjectId;
          if (Environment.appwriteApiKey.isNotEmpty) req.headers['x-appwrite-key'] = Environment.appwriteApiKey;
          final cookie = await AppwriteService.getSessionCookie();
          if (cookie != null && cookie.isNotEmpty) req.headers['cookie'] = cookie;
        }
      } catch (_) {}

      final resp = await client.send(req);
      if (resp.statusCode != 200) {
        if (kDebugMode) debugPrint('APK download request failed: ${resp.statusCode}');
        return null;
      }
      final contentLength = resp.contentLength ?? 0;
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/update_${DateTime.now().millisecondsSinceEpoch}.apk');
      final sink = file.openWrite();
      int received = 0;
      await for (final chunk in resp.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (onProgress != null && contentLength > 0) onProgress(received / contentLength);
      }
      await sink.close();
      return file.path;
    } catch (e) {
      if (kDebugMode) debugPrint('APK download failed: $e');
      return null;
    }
  }

  static Future<bool> verifySha256(String filePath, String expectedHex) async {
    try {
      final f = File(filePath);
      if (!await f.exists()) return false;
      final bytes = await f.readAsBytes();
      final digest = sha256.convert(bytes);
      return digest.toString().toLowerCase() == expectedHex.toLowerCase();
    } catch (e) {
      if (kDebugMode) debugPrint('sha256 verify failed: $e');
      return false;
    }
  }

  // Ask platform to install the APK (Android). Returns true if the platform acknowledged the request.
  static Future<bool> installApk(String apkPath) async {
    try {
      final res = await _channel.invokeMethod<bool>('installApk', {'path': apkPath});
      return res == true;
    } catch (e) {
      if (kDebugMode) debugPrint('installApk failed: $e');
      return false;
    }
  }

  // Simple semver-ish comparison: returns true if a > b
  static bool _isNewer(String a, String b) {
    try {
      // Normalize versions: strip build metadata (+...) and pre-release suffixes
      String norm(String v) {
        var s = v.split('+').first.split('-').first.trim();
        return s;
      }
      final pa = norm(a).split('.').map(int.tryParse).map((e) => e ?? 0).toList();
      final pb = norm(b).split('.').map(int.tryParse).map((e) => e ?? 0).toList();
      final n = pa.length > pb.length ? pa.length : pb.length;
      for (var i = 0; i < n; i++) {
        final va = i < pa.length ? pa[i] : 0;
        final vb = i < pb.length ? pb[i] : 0;
        if (va > vb) return true;
        if (va < vb) return false;
      }
    } catch (_) {}
    return false;
  }
}

// Helper widget that shows a dialog and triggers download+install when user confirms
class UpdateDialog {
  static Future<void> showIfAvailable(BuildContext context) async {
    if (kDebugMode) debugPrint('UpdateDialog: showIfAvailable called');
    final info = await UpdateService.checkForUpdate();
    if (info == null) return;
    if (!context.mounted) return;
    // Push a full-screen update page that looks like Telegram's update prompt
    Navigator.of(context).push(MaterialPageRoute(builder: (c) => UpdateScreen(info: info)));
  }
}

// Progress overlay removed; UpdateScreen handles download/install UI.
