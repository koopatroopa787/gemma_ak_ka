import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'pharos_prompts.dart';
import 'model_settings.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PharosVisionService
//
// Flutter-side bridge to the Kotlin LiteRT-LM module.
// Commands go via MethodChannel; streaming tokens come back via EventChannel.
//
// Usage:
//   final svc = PharosVisionService();
//   await svc.initialize(modelPath, settings);
//   final json = await svc.analyzePackage(imageBytes);
// ─────────────────────────────────────────────────────────────────────────────
class PharosVisionService {
  static const MethodChannel _method = MethodChannel('com.pharos/litert');
  static const EventChannel  _event  = EventChannel('com.pharos/inference_stream');

  // Observable state — scanner_screen watches these via AnimatedBuilder.
  final ValueNotifier<bool>   isLoading     = ValueNotifier<bool>(false);
  final ValueNotifier<bool>   isInitialized = ValueNotifier<bool>(false);
  final ValueNotifier<String> status        = ValueNotifier<String>('Not initialized');
  // Which hardware backend is actually running ("GPU" or "CPU").
  final ValueNotifier<String> activeBackend = ValueNotifier<String>('—');

  // Lazily created broadcast stream — shared across all analyzePackage calls.
  Stream<Map<Object?, Object?>>? _stream;
  Stream<Map<Object?, Object?>> get _tokenStream {
    _stream ??= _event
        .receiveBroadcastStream()
        .map((dynamic e) => e as Map<Object?, Object?>);
    return _stream!;
  }

  // ── Initialize ───────────────────────────────────────────────────────────

  Future<void> initialize(String modelPath, ModelSettings settings) async {
    isLoading.value = true;
    status.value = 'Loading Gemma 4 model…';
    try {
      final Object? result = await _method.invokeMethod<Object>(
        'initialize',
        <String, dynamic>{'modelPath': modelPath, ...settings.toMap()},
      );

      // Kotlin returns {"usedCpu": bool, "backend": String}
      if (result is Map) {
        final String backend = (result['backend'] as String?) ?? '—';
        final bool usedCpu   = (result['usedCpu'] as bool?) ?? false;
        activeBackend.value  = backend;
        status.value = usedCpu
            ? 'Ready (CPU — GPU unavailable on this device)'
            : 'Ready (GPU)';
      } else {
        status.value = 'Ready';
      }

      isInitialized.value = true;
    } on PlatformException catch (e) {
      status.value = 'Load failed: ${e.message}';
      isInitialized.value = false;
      rethrow;
    } finally {
      isLoading.value = false;
    }
  }

  // ── Analyze a blister-pack image ─────────────────────────────────────────

  /// Runs on-device Gemma 4 vision inference on [imageBytes] and returns
  /// the raw JSON string produced by the model (tokens streamed and assembled).
  Future<String> analyzePackage(List<int> imageBytes) async {
    if (!isInitialized.value) throw Exception('Model not initialized');

    status.value = 'Analyzing…';

    final StringBuffer buffer = StringBuffer();
    final Completer<String> completer = Completer<String>();

    // Listen to the token stream BEFORE triggering inference so we don't
    // miss any tokens that arrive very quickly.
    final StreamSubscription<Map<Object?, Object?>> sub = _tokenStream.listen(
      (Map<Object?, Object?> event) {
        final String? type = event['type'] as String?;
        if (type == 'token') {
          buffer.write(event['value'] as String? ?? '');
        } else if (type == 'done' && !completer.isCompleted) {
          completer.complete(buffer.toString());
        }
      },
      onError: (Object error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
    );

    try {
      await _method.invokeMethod<void>('analyzeImage', <String, dynamic>{
        'imageBytes': Uint8List.fromList(imageBytes),
        'systemPrompt': kPharosSystemPrompt,
        'userPrompt':
            'Analyse this pharmaceutical blister pack and return your '
            'assessment as a JSON object strictly following the schema.',
      });
    } on PlatformException catch (e) {
      await sub.cancel();
      status.value = 'Ready';
      throw Exception('Inference failed: ${e.message}');
    }

    // Wait for the stream to signal done.
    // CPU inference on Gemma 4 E2B typically takes 1-5 min on mid-range devices.
    // GPU would be ~30 s but we fall back to CPU. 8 min is generous but safe.
    final String result = await completer.future.timeout(
      const Duration(minutes: 8),
      onTimeout: () => throw TimeoutException('Model did not respond in 8 min'),
    );

    await sub.cancel();
    status.value = 'Ready';
    return result;
  }

  // ── Update settings without reloading the model ──────────────────────────

  Future<void> applySettings(ModelSettings settings) async {
    try {
      await _method.invokeMethod<void>('resetSession', settings.toMap());
    } on PlatformException catch (e) {
      debugPrint('resetSession failed: ${e.message}');
    }
  }

  // ── Cleanup ──────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    try {
      await _method.invokeMethod<void>('dispose');
    } catch (_) {}
    isLoading.dispose();
    isInitialized.dispose();
    status.dispose();
    activeBackend.dispose();
  }
}
