import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/offline_voice_pack.dart';

/// Downloads data, never executable code. Files become usable only after SHA-256 verification.
class OfflineModelStore extends ChangeNotifier {
  OfflineModelStore({
    Directory? directory,
    http.Client Function()? clientFactory,
    this.files = OfflineVoicePack.files,
    this.baseUrl = OfflineVoicePack.baseUrl,
  }) : _directory = directory,
       _clientFactory = clientFactory ?? http.Client.new;

  Directory? _directory;
  final http.Client Function() _clientFactory;
  final List<VoicePackFile> files;
  final String baseUrl;
  http.Client? _client;
  bool _cancelled = false;
  bool _disposed = false;
  bool ready = false;
  bool downloading = false;
  bool checking = false;
  int receivedBytes = 0;
  String? currentFile;
  String? error;
  Future<void>? _initializing;

  String? get directoryPath => _directory?.path;
  int get totalBytes => files.fold(0, (sum, file) => sum + file.bytes);
  double get progress =>
      totalBytes == 0 ? 0 : (receivedBytes / totalBytes).clamp(0, 1);

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    try {
      _directory ??= Directory(
        '${(await getApplicationSupportDirectory()).path}/voices/${OfflineVoicePack.id}',
      );
      final marker = File('${_directory!.path}/verified');
      ready =
          await marker.exists() &&
          await marker.readAsString() == OfflineVoicePack.revision;
      for (final asset in files) {
        final file = File('${_directory!.path}/${asset.path}');
        if (!await file.exists() || await file.length() != asset.bytes) {
          ready = false;
        }
      }
    } catch (_) {
      ready = false;
      error = 'Voice storage is not available.';
    }
    _notify();
  }

  Future<void> download() async {
    if (downloading || checking) return;
    downloading = true;
    _cancelled = false;
    receivedBytes = 0;
    error = null;
    _notify();
    try {
      await initialize();
      final directory = _directory;
      if (directory == null) throw StateError('Storage unavailable');
      await directory.create(recursive: true);
      _client = _clientFactory();
      for (final asset in files) {
        _ensureActive();
        currentFile = asset.path.split('/').last;
        final target = File('${directory.path}/${asset.path}');
        if (await _isValid(target, asset)) {
          receivedBytes += asset.bytes;
          _notify();
          continue;
        }
        await target.parent.create(recursive: true);
        final partial = File('${target.path}.part');
        final response = await _client!
            .send(http.Request('GET', Uri.parse('$baseUrl/${asset.path}')))
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          throw HttpException('HTTP ${response.statusCode}');
        }
        if (response.contentLength != null &&
            response.contentLength != asset.bytes) {
          throw const FormatException('Unexpected model size');
        }
        var count = 0;
        final sink = partial.openWrite();
        var lastNotify = DateTime.now();
        try {
          await for (final bytes in response.stream.timeout(
            const Duration(seconds: 45),
          )) {
            _ensureActive();
            count += bytes.length;
            if (count > asset.bytes) {
              throw const FormatException('Model file is too large');
            }
            sink.add(bytes);
            receivedBytes += bytes.length;
            if (DateTime.now().difference(lastNotify).inMilliseconds >= 150) {
              lastNotify = DateTime.now();
              await sink.flush();
              _notify();
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        _ensureActive();
        if (!await _isValid(partial, asset)) {
          await partial.delete();
          throw const FormatException('Download verification failed');
        }
        _ensureActive();
        if (await target.exists()) await target.delete();
        await partial.rename(target.path);
      }
      _ensureActive();
      await File(
        '${directory.path}/verified',
      ).writeAsString(OfflineVoicePack.revision, flush: true);
      ready = true;
    } catch (_) {
      error = _cancelled
          ? 'Download cancelled. Verified files are kept for retry.'
          : 'Voice download failed. Check your connection and free storage, then retry.';
    } finally {
      _client?.close();
      _client = null;
      downloading = false;
      currentFile = null;
      _notify();
    }
  }

  void cancel() {
    _cancelled = true;
    _client?.close();
  }

  void _ensureActive() {
    if (_cancelled || _disposed) throw StateError('Cancelled');
  }

  Future<bool> _isValid(File file, VoicePackFile asset) async {
    if (!await file.exists() || await file.length() != asset.bytes) {
      return false;
    }
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == asset.sha256;
  }

  Future<void> remove() async {
    if (downloading || checking) return;
    await initialize();
    try {
      // Delete only the model directory owned by this store, never a download URL.
      if (_directory != null && await _directory!.exists()) {
        await _directory!.delete(recursive: true);
      }
      ready = false;
      receivedBytes = 0;
      error = null;
    } catch (_) {
      error = 'Could not delete the voice pack. Stop playback and try again.';
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}
