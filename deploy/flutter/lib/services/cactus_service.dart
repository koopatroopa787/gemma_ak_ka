import 'package:flutter/foundation.dart';
import 'package:cactus/cactus.dart';

class CactusService {
  late CactusVLM _model;
  final isLoading = ValueNotifier<bool>(false);
  final isInitialized = ValueNotifier<bool>(false);
  final status = ValueNotifier<String>('Initializing...');

  static const int visionTokenBudget = 560;
  static const int maxTokens = 1024;
  static const double temperature = 0.1;

  Future<void> initialize() async {
    try {
      isLoading.value = true;
      status.value = 'Loading Gemma 4 model...';

      _model = CactusVLM();
      
      isInitialized.value = true;
      status.value = 'Ready';
      isLoading.value = false;
    } catch (e) {
      status.value = 'Failed: $e';
      isLoading.value = false;
    }
  }

  Future<String> analyzePackage(
    List<int> imageBytes,
    String systemPrompt,
  ) async {
    if (!isInitialized.value) {
      throw Exception('Model not initialized');
    }

    try {
      final base64Image = base64Encode(imageBytes);
      final prompt = '''$systemPrompt

Image: data:image/jpeg;base64,$base64Image

Analyse this pharmaceutical blister pack and return your assessment as a JSON object.''';

      final response = await _model.completion([
        ChatMessage(role: 'system', content: systemPrompt),
        ChatMessage(role: 'user', content: prompt),
      ]);

      return response.toString();
    } catch (e) {
      throw Exception('Analysis failed: $e');
    }
  }

  void dispose() {
    isLoading.dispose();
    isInitialized.dispose();
    status.dispose();
  }
}

String base64Encode(List<int> bytes) {
  // Simple base64 encoding
  const String chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  StringBuffer result = StringBuffer();

  int i = 0;
  while (i < bytes.length) {
    int b1 = bytes[i++];
    int? b2 = i < bytes.length ? bytes[i++] : null;
    int? b3 = i < bytes.length ? bytes[i++] : null;

    int n = (b1 << 16) | ((b2 ?? 0) << 8) | (b3 ?? 0);

    int c1 = (n >> 18) & 63;
    int c2 = (n >> 12) & 63;
    int c3 = b2 != null ? (n >> 6) & 63 : 64;
    int c4 = b3 != null ? n & 63 : 64;

    result.write(chars[c1]);
    result.write(chars[c2]);
    result.write(c3 < 64 ? chars[c3] : '=');
    result.write(c4 < 64 ? chars[c4] : '=');
  }

  return result.toString();
}
