import 'package:flutter/material.dart';

import '../services/model_manager.dart';
import '../services/model_settings.dart';
import '../services/pharos_vision_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SettingsScreen
//
// Mirrors the AI Edge Gallery "Configs updated" panel exactly:
//   • Max tokens  (slider, 256 – 17710)
//   • TopK        (slider, 1 – 100)
//   • TopP        (slider, 0.0 – 1.0)
//   • Temperature (slider, 0.0 – 2.0)
//   • Accelerator (GPU / CPU toggle)
//   • Enable thinking (switch)
//   • Model info card + delete button
// ─────────────────────────────────────────────────────────────────────────────
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settingsService,
    required this.visionService,
  });

  final ModelSettingsService settingsService;
  final PharosVisionService visionService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late ModelSettings _draft;
  bool _hasChanges = false;
  bool _isSaving = false;
  List<String> _lastChanges = <String>[];

  @override
  void initState() {
    super.initState();
    _draft = widget.settingsService.settings;
  }

  void _markChanged(ModelSettings updated) {
    setState(() {
      _draft = updated;
      _hasChanges = true;
    });
  }

  Future<void> _applyChanges() async {
    setState(() => _isSaving = true);
    try {
      _lastChanges = widget.settingsService.settings.diff(_draft);
      await widget.settingsService.update(_draft);
      // Push new session config to the native engine (no model reload needed).
      await widget.visionService.applySettings(_draft);
      setState(() {
        _hasChanges = false;
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1B5E20),
            content: Text(
              _lastChanges.isNotEmpty
                  ? 'Configs updated: ${_lastChanges.join(', ')}'
                  : 'Settings saved',
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to apply: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
      children: <Widget>[
        // ── Page header ─────────────────────────────────────────────────────
        const Text(
          'Model Settings',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: Color(0xFF191C1E),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Configure inference parameters — changes apply without reloading.',
          style: TextStyle(color: Color(0xFF575F6B)),
        ),

        // ── "Configs updated" banner (shown after apply) ─────────────────
        if (_lastChanges.isNotEmpty && !_hasChanges) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1B5E20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Configs updated',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                ..._lastChanges.map(
                  (String change) => Text(
                    '• $change',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),

        // ── Inference parameters ────────────────────────────────────────────
        _card(
          title: 'Inference Parameters',
          children: <Widget>[
            _sliderRow(
              label: 'Max tokens',
              value: _draft.maxTokens.toDouble(),
              min: 256,
              max: 17710,
              divisions: 170,
              display: '${_draft.maxTokens}',
              onChanged: (double v) =>
                  _markChanged(_draft.copyWith(maxTokens: v.round())),
            ),
            _sliderRow(
              label: 'TopK',
              value: _draft.topK.toDouble(),
              min: 1,
              max: 100,
              divisions: 99,
              display: '${_draft.topK}',
              onChanged: (double v) =>
                  _markChanged(_draft.copyWith(topK: v.round())),
            ),
            _sliderRow(
              label: 'TopP',
              value: _draft.topP,
              min: 0.0,
              max: 1.0,
              divisions: 100,
              display: _draft.topP.toStringAsFixed(2),
              onChanged: (double v) =>
                  _markChanged(_draft.copyWith(topP: v)),
            ),
            _sliderRow(
              label: 'Temperature',
              value: _draft.temperature,
              min: 0.0,
              max: 2.0,
              divisions: 200,
              display: _draft.temperature.toStringAsFixed(2),
              onChanged: (double v) =>
                  _markChanged(_draft.copyWith(temperature: v)),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // ── Runtime options ─────────────────────────────────────────────────
        _card(
          title: 'Runtime',
          children: <Widget>[
            // Accelerator toggle (GPU / CPU)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Accelerator',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'GPU is faster; CPU works on all devices.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF727784)),
                        ),
                      ],
                    ),
                  ),
                  SegmentedButton<bool>(
                    segments: const <ButtonSegment<bool>>[
                      ButtonSegment<bool>(value: true,  label: Text('GPU')),
                      ButtonSegment<bool>(value: false, label: Text('CPU')),
                    ],
                    selected: <bool>{_draft.useGpu},
                    onSelectionChanged: (Set<bool> s) =>
                        _markChanged(_draft.copyWith(useGpu: s.first)),
                    style: ButtonStyle(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Enable thinking
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Enable thinking',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Extended reasoning mode — adds latency, increases accuracy.',
                style: TextStyle(fontSize: 12),
              ),
              value: _draft.enableThinking,
              onChanged: (bool v) =>
                  _markChanged(_draft.copyWith(enableThinking: v)),
              activeThumbColor: const Color(0xFF1A6BCC),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // ── Model file info ─────────────────────────────────────────────────
        _ModelInfoCard(visionService: widget.visionService),

        const SizedBox(height: 20),

        // ── Apply button ─────────────────────────────────────────────────────
        ElevatedButton(
          onPressed: _hasChanges && !_isSaving ? _applyChanges : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A6BCC),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : const Text('Apply Changes'),
        ),

        if (_hasChanges)
          TextButton(
            onPressed: () => setState(() {
              _draft = widget.settingsService.settings;
              _hasChanges = false;
            }),
            child: const Text('Discard'),
          ),
      ],
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _card({required String title, required List<Widget> children}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFC2C6D4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: Color(0xFF575F6B),
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAEFFF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    display,
                    style: const TextStyle(
                      color: Color(0xFF0053A6),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              activeColor: const Color(0xFF1A6BCC),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _ModelInfoCard — shows download status, file size, and a delete button.
// ─────────────────────────────────────────────────────────────────────────────
class _ModelInfoCard extends StatefulWidget {
  const _ModelInfoCard({required this.visionService});

  final PharosVisionService visionService;

  @override
  State<_ModelInfoCard> createState() => _ModelInfoCardState();
}

class _ModelInfoCardState extends State<_ModelInfoCard> {
  bool? _ready;
  int _sizeBytes = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final bool ready = await ModelManager.isModelReady();
    final int size = await ModelManager.existingFileSize();
    if (mounted) {
      setState(() {
        _ready = ready;
        _sizeBytes = size;
      });
    }
  }

  String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final bool ready = _ready ?? false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC2C6D4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'MODEL',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: Color(0xFF575F6B),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Icon(
                ready ? Icons.check_circle : Icons.downloading,
                color: ready ? const Color(0xFF2E7D32) : const Color(0xFF1A6BCC),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Gemma-4-E2B-it',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      ready
                          ? '${_fmt(_sizeBytes)} · LiteRT-LM format'
                          : _sizeBytes > 0
                              ? '${_fmt(_sizeBytes)} downloaded (incomplete)'
                              : 'Not downloaded',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF727784)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (ready) ...<Widget>[
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: widget.visionService.isInitialized,
              builder: (_, __) {
                final bool initialized = widget.visionService.isInitialized.value;
                return Row(
                  children: <Widget>[
                    Icon(
                      initialized ? Icons.bolt : Icons.hourglass_empty,
                      size: 16,
                      color: initialized
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFFF57F17),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      initialized ? 'Engine running' : 'Engine not loaded',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF575F6B)),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final bool confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Delete model?'),
                        content: const Text(
                            'This will free ~2.6 GB but requires a re-download to use Pharos offline.'),
                        actions: <Widget>[
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel')),
                          TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Delete',
                                  style:
                                      TextStyle(color: Color(0xFFB71C1C)))),
                        ],
                      ),
                    ) ??
                    false;

                if (confirm) {
                  await ModelManager.deleteModel();
                  await _refresh();
                }
              },
              icon: const Icon(Icons.delete_outline,
                  color: Color(0xFFB71C1C), size: 18),
              label: const Text('Delete model file',
                  style: TextStyle(color: Color(0xFFB71C1C))),
            ),
          ],
        ],
      ),
    );
  }
}
