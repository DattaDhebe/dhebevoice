import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:text_reader_app/models/offline_voice_pack.dart';
import 'package:text_reader_app/services/offline_model_store.dart';

void main() {
  late Directory directory;
  late List<VoicePackFile> files;
  final bytes = utf8.encode('test model');
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dhebevoice-model-test-');
    files = [
      VoicePackFile(
        'onnx/test.onnx',
        bytes.length,
        sha256.convert(bytes).toString(),
      ),
    ];
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('only verified downloads become ready and are reusable', () async {
    var requests = 0;
    final store = OfflineModelStore(
      directory: directory,
      files: files,
      clientFactory: () => MockClient((_) async {
        requests++;
        return http.Response.bytes(bytes, 200);
      }),
    );
    await store.download();
    expect(store.ready, isTrue);
    expect(store.progress, 1);
    expect(store.error, isNull);
    await store.download();
    expect(requests, 1);
    final restored = OfflineModelStore(directory: directory, files: files);
    await restored.initialize();
    expect(restored.ready, isTrue);
    await restored.remove();
    expect(restored.ready, isFalse);
    expect(await directory.exists(), isFalse);
    restored.dispose();
    store.dispose();
  });

  test('wrong hash never enables the model', () async {
    final store = OfflineModelStore(
      directory: directory,
      files: files,
      clientFactory: () => MockClient(
        (_) async => http.Response.bytes(List.filled(bytes.length, 0), 200),
      ),
    );
    await store.download();
    expect(store.ready, isFalse);
    expect(store.error, isNotNull);
    expect(await File('${directory.path}/verified').exists(), isFalse);
    store.dispose();
  });

  test('cancellation cannot mark an in-flight download ready', () async {
    final response = Completer<http.Response>();
    final requested = Completer<void>();
    final store = OfflineModelStore(
      directory: directory,
      files: files,
      clientFactory: () => MockClient((_) {
        requested.complete();
        return response.future;
      }),
    );
    final downloading = store.download();
    await requested.future;
    store.cancel();
    response.complete(http.Response.bytes(bytes, 200));
    await downloading;
    expect(store.downloading, isFalse);
    expect(store.ready, isFalse);
    expect(store.error, contains('cancelled'));
    store.dispose();
  });

  test('HTTP errors can be retried without stale ready state', () async {
    var fails = true;
    final store = OfflineModelStore(
      directory: directory,
      files: files,
      clientFactory: () => MockClient(
        (_) async =>
            fails ? http.Response('', 503) : http.Response.bytes(bytes, 200),
      ),
    );
    await store.download();
    expect(store.ready, isFalse);
    fails = false;
    await store.download();
    expect(store.ready, isTrue);
    expect(store.error, isNull);
    store.dispose();
  });
}
