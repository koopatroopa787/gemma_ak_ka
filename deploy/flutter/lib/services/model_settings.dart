import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ModelSettings — immutable snapshot of all tunable parameters.
// Mirrors the AI Edge Gallery "Configs updated" panel exactly.
// ─────────────────────────────────────────────────────────────────────────────
@immutable
class ModelSettings {
  const ModelSettings({
    this.maxTokens = 4096,
    this.topK = 64,
    this.topP = 0.95,
    this.temperature = 1.0,
    this.enableThinking = false,
    this.useGpu = true,
  });

  final int maxTokens;       // context window / max output tokens
  final int topK;            // top-K sampling (1 – 100)
  final double topP;         // nucleus sampling (0.0 – 1.0)
  final double temperature;  // creativity (0.0 – 2.0)
  final bool enableThinking; // extended reasoning (Gemma 4 supports this)
  final bool useGpu;         // GPU vs CPU inference

  ModelSettings copyWith({
    int? maxTokens,
    int? topK,
    double? topP,
    double? temperature,
    bool? enableThinking,
    bool? useGpu,
  }) =>
      ModelSettings(
        maxTokens: maxTokens ?? this.maxTokens,
        topK: topK ?? this.topK,
        topP: topP ?? this.topP,
        temperature: temperature ?? this.temperature,
        enableThinking: enableThinking ?? this.enableThinking,
        useGpu: useGpu ?? this.useGpu,
      );

  /// Human-readable diff used for the "Configs updated" banner.
  List<String> diff(ModelSettings other) {
    final List<String> changes = <String>[];
    if (maxTokens != other.maxTokens) {
      changes.add('Max tokens: $maxTokens → ${other.maxTokens}');
    }
    if (topK != other.topK) changes.add('TopK: $topK → ${other.topK}');
    if ((topP - other.topP).abs() > 0.001) {
      changes.add('TopP: ${topP.toStringAsFixed(2)} → ${other.topP.toStringAsFixed(2)}');
    }
    if ((temperature - other.temperature).abs() > 0.001) {
      changes.add(
          'Temperature: ${temperature.toStringAsFixed(2)} → ${other.temperature.toStringAsFixed(2)}');
    }
    if (enableThinking != other.enableThinking) {
      changes.add(
          'Thinking: ${enableThinking ? "on" : "off"} → ${other.enableThinking ? "on" : "off"}');
    }
    if (useGpu != other.useGpu) {
      changes.add('Accelerator: ${useGpu ? "GPU" : "CPU"} → ${other.useGpu ? "GPU" : "CPU"}');
    }
    return changes;
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'maxTokens': maxTokens,
        'topK': topK,
        'topP': topP,
        'temperature': temperature,
        'enableThinking': enableThinking,
        'useGpu': useGpu,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// ModelSettingsService — loads/saves settings from SharedPreferences and
// notifies listeners when they change.
// ─────────────────────────────────────────────────────────────────────────────
class ModelSettingsService extends ChangeNotifier {
  ModelSettings _settings = const ModelSettings();
  ModelSettings get settings => _settings;

  // Last confirmed diff for the "Configs updated" banner.
  List<String> lastChanges = <String>[];

  Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _settings = ModelSettings(
      maxTokens: prefs.getInt('ph_maxTokens') ?? 4096,
      topK: prefs.getInt('ph_topK') ?? 64,
      topP: prefs.getDouble('ph_topP') ?? 0.95,
      temperature: prefs.getDouble('ph_temperature') ?? 1.0,
      enableThinking: prefs.getBool('ph_enableThinking') ?? false,
      useGpu: prefs.getBool('ph_useGpu') ?? true,
    );
    notifyListeners();
  }

  Future<void> update(ModelSettings newSettings) async {
    lastChanges = _settings.diff(newSettings);
    _settings = newSettings;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ph_maxTokens', newSettings.maxTokens);
    await prefs.setInt('ph_topK', newSettings.topK);
    await prefs.setDouble('ph_topP', newSettings.topP);
    await prefs.setDouble('ph_temperature', newSettings.temperature);
    await prefs.setBool('ph_enableThinking', newSettings.enableThinking);
    await prefs.setBool('ph_useGpu', newSettings.useGpu);
    notifyListeners();
  }
}
