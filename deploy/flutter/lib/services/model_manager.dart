import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ModelManager — downloads and validates the Gemma 4 E2B .litertlm model.
//
// Confirmed URL (litert-community HuggingFace, no auth required):
//   https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/
//                         resolve/main/gemma-4-E2B-it.litertlm
//   Size: ~2.59 GB
//
// Runtime compatibility note:
//   These model files were built for litertlm-android 0.0.4-experimental.
//   Using "latest.release" of the runtime WILL cause "Invalid magic number"
//   because the flatbuffer schema changed between versions.
//   See android/app/build.gradle.kts for the pinned runtime version.
// ─────────────────────────────────────────────────────────────────────────────
class ModelManager {
  static const String _modelFileName = 'gemma-4-E2B-it.litertlm';

  static const String _modelUrl =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm'
      '/resolve/main/gemma-4-E2B-it.litertlm';

  /// Minimum valid size — a real 2.59 GB model.
  /// Anything below 2 GB is definitely wrong (HTML error page, GGUF, partial).
  static const int _minBytes = 2000000000; // 2 GB

  // ── Path helpers ─────────────────────────────────────────────────────────

  static Future<Directory> _modelsDir() async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/models');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<String> modelPath() async {
    final Directory dir = await _modelsDir();
    return '${dir.path}/$_modelFileName';
  }

  // ── Format validation ─────────────────────────────────────────────────────
  //
  // We only reject files that are OBVIOUSLY wrong:
  //   • Too small (< 2 GB)    → HTML error page, empty, truncated
  //   • GGUF magic "GGUF"     → llama.cpp format, incompatible runtime
  //   • HTML/JSON prefix      → download returned an error page
  //
  // We do NOT reject based on specific flatbuffer bytes — the .litertlm
  // format starts with a flatbuffer root offset that varies per model.
  // The engine itself is the authoritative format checker.
  //
  // Returns null on success, or an error description string on failure.
  // ─────────────────────────────────────────────────────────────────────────

  static Future<String?> checkFormat() async {
    final String path = await modelPath();
    final File file = File(path);
    if (!file.existsSync()) return 'File not found';

    final int size = file.lengthSync();
    if (size < _minBytes) {
      final String mb = (size / 1024 / 1024).toStringAsFixed(1);
      return 'File too small ($mb MB — expected ~2590 MB).\n'
          'The download may have been interrupted. Delete and re-download.';
    }

    // Read first 8 bytes for quick sanity checks.
    final RandomAccessFile raf = await file.open();
    final Uint8List h = Uint8List(8);
    await raf.readInto(h);
    await raf.close();

    // GGUF magic = "GGUF" (0x47 0x47 0x55 0x46)
    if (h[0] == 0x47 && h[1] == 0x47 && h[2] == 0x55 && h[3] == 0x46) {
      return 'GGUF format detected — this is a llama.cpp model.\n'
          'LiteRT-LM needs the .litertlm format.\n'
          'Delete and re-download, or select the correct file.';
    }

    // HTML / JSON error page (e.g. 401 Unauthorised returned as HTML)
    if (h[0] == 0x3C || // '<' → <html
        h[0] == 0x7B || // '{' → {"error":...}
        h[0] == 0x0A || // newline → text response
        (h[0] == 0x76 && h[1] == 0x65 && h[2] == 0x72)) { // "ver" → LFS pointer
      return 'Downloaded file appears to be a text/HTML response, not a model.\n'
          'The download URL may have returned an error. Delete and re-download.';
    }

    return null; // Looks OK — let the engine decide.
  }

  // ── Status ────────────────────────────────────────────────────────────────

  static Future<bool> isModelReady() async {
    final String path = await modelPath();
    final File file = File(path);
    if (!file.existsSync()) return false;
    if (file.lengthSync() < _minBytes) return false;
    return await checkFormat() == null;
  }

  static Future<int> existingFileSize() async {
    final String path = await modelPath();
    final File file = File(path);
    return file.existsSync() ? file.lengthSync() : 0;
  }

  // ── Download ─────────────────────────────────────────────────────────────

  static Future<void> downloadModel({
    required void Function(double progress, int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final String path = await modelPath();
    final File file = File(path);

    // If file exists and is valid, nothing to do.
    if (file.existsSync() && file.lengthSync() >= _minBytes) {
      final String? err = await checkFormat();
      if (err == null) return; // already complete and valid
      // Wrong format — delete and start fresh.
      file.deleteSync();
    }

    // Resume partial download if file already exists and is partial.
    int existingSize = 0;
    if (file.existsSync()) {
      existingSize = file.lengthSync();
    }

    final Map<String, dynamic> headers = <String, dynamic>{
      'User-Agent': 'Pharos-App/1.0',
      // Resume support — HuggingFace CDN honours Range requests.
      if (existingSize > 0) 'Range': 'bytes=$existingSize-',
    };

    try {
      await Dio().download(
        _modelUrl,
        path,
        cancelToken: cancelToken,
        deleteOnError: false, // keep partial file for resume on next attempt
        onReceiveProgress: (int received, int total) {
          final int actualReceived = received + existingSize;
          final int actualTotal = total > 0 ? total + existingSize : -1;
          final double progress =
              actualTotal > 0 ? actualReceived / actualTotal : 0.0;
          onProgress(progress, actualReceived, actualTotal);
        },
        options: Options(
          headers: headers,
          followRedirects: true,         // follow HuggingFace CDN redirects
          maxRedirects: 10,
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(hours: 3),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return; // user cancelled
      rethrow;
    }
  }

  // ── Copy from file picker ─────────────────────────────────────────────────

  static Future<String?> copyFromDevicePath(String sourcePath) async {
    final File source = File(sourcePath);
    if (!source.existsSync()) return 'File not found: $sourcePath';
    final String destPath = await modelPath();
    final File dest = File(destPath);
    if (dest.existsSync()) dest.deleteSync();
    try {
      await source.copy(destPath);
    } catch (e) {
      return 'Copy failed: $e';
    }
    return await checkFormat();
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  static Future<void> deleteModel() async {
    final String path = await modelPath();
    final File file = File(path);
    if (file.existsSync()) file.deleteSync();
  }
}
