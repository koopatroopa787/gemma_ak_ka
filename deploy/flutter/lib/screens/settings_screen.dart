// ── FILE: lib/screens/settings_screen.dart ──
import 'package:flutter/material.dart';

import '../services/model_manager.dart';
import '../services/model_settings.dart';
import '../services/pharos_vision_service.dart';

// ── Design tokens ─────────────────────────────────────────────────────────
const Color _kSurface = Color(0xFFFFFFFF);
const Color _kNavy    = Color(0xFF0B1629);
const Color _kSlate   = Color(0xFF475569);
const Color _kMuted   = Color(0xFF94A3B8);
const Color _kBorder  = Color(0xFFE2E8F0);
const Color _kBlue1   = Color(0xFF1D4ED8);
const Color _kBlue3   = Color(0xFFEFF6FF);

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
            backgroundColor: const Color(0xFF065F46),
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
    return Stack(
      children: <Widget>[
        ListView(
          padding: EdgeInsets.fromLTRB(
              16, 20, 16, _hasChanges ? 100 : 40),
          children: <Widget>[
            // ── Page header ───────────────────────────────────────────────
            const Text(
              'Settings',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: _kNavy,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Configure inference parameters — changes apply without reloading.',
              style: TextStyle(color: _kSlate, fontSize: 14),
            ),

            // ── "Configs updated" banner ──────────────────────────────────
            if (_lastChanges.isNotEmpty && !_hasChanges) ...<Widget>[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF6EE7B7)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Configs updated',
                      style: TextStyle(
                        color: Color(0xFF065F46),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ..._lastChanges.map(
                      (String change) => Text(
                        '• $change',
                        style: const TextStyle(
                            color: Color(0xFF065F46), fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ── Inference parameters ──────────────────────────────────────
            _SectionCard(
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

            // ── Runtime options ───────────────────────────────────────────
            _SectionCard(
              title: 'Runtime',
              children: <Widget>[
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
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _kNavy),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'GPU is faster; CPU works on all devices.',
                              style:
                                  TextStyle(fontSize: 12, color: _kMuted),
                            ),
                          ],
                        ),
                      ),
                      SegmentedButton<bool>(
                        segments: const <ButtonSegment<bool>>[
                          ButtonSegment<bool>(
                              value: true, label: Text('GPU')),
                          ButtonSegment<bool>(
                              value: false, label: Text('CPU')),
                        ],
                        selected: <bool>{_draft.useGpu},
                        onSelectionChanged: (Set<bool> s) =>
                            _markChanged(_draft.copyWith(useGpu: s.first)),
                        style: ButtonStyle(
                          tapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: _kBorder),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Enable thinking',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: _kNavy),
                  ),
                  subtitle: const Text(
                    'Extended reasoning mode — adds latency, increases accuracy.',
                    style: TextStyle(fontSize: 12, color: _kMuted),
                  ),
                  value: _draft.enableThinking,
                  onChanged: (bool v) =>
                      _markChanged(_draft.copyWith(enableThinking: v)),
                  activeThumbColor: _kBlue1,
                  activeTrackColor: _kBlue1.withValues(alpha: 0.4),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Model file info ───────────────────────────────────────────
            _ModelInfoCard(visionService: widget.visionService),

            // Extra bottom space so content isn't hidden by floating button
            const SizedBox(height: 12),
          ],
        ),

        // ── Floating Apply button (appears only when _hasChanges) ──────────
        if (_hasChanges)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _GradientButton(
                      isSaving: _isSaving,
                      onPressed:
                          _hasChanges && !_isSaving ? _applyChanges : null,
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: TextButton(
                        onPressed: () => setState(() {
                          _draft = widget.settingsService.settings;
                          _hasChanges = false;
                        }),
                        child: const Text(
                          'Discard',
                          style: TextStyle(color: _kMuted),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                label,
                style: const TextStyle(
                    fontWeight: FontWeight.w500, color: _kNavy),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _kBlue3,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  display,
                  style: const TextStyle(
                    color: _kBlue1,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _kBlue1,
              inactiveTrackColor: _kBorder,
              thumbColor: _kBlue1,
              overlayColor: _kBlue1.withValues(alpha: 0.12),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section card ──────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.all(Radius.circular(16)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 24,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Section label with blue left accent bar
          Row(
            children: <Widget>[
              Container(
                width: 3,
                height: 14,
                decoration: const BoxDecoration(
                  color: _kBlue1,
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: _kMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

// ── Gradient apply button ─────────────────────────────────────────────────

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.isSaving,
    required this.onPressed,
  });

  final bool isSaving;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        gradient: onPressed != null
            ? const LinearGradient(
                colors: <Color>[_kBlue1, Color(0xFF2563EB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: onPressed == null ? const Color(0xFFE2E8F0) : null,
        borderRadius: BorderRadius.circular(999),
        boxShadow: onPressed != null
            ? const <BoxShadow>[
                BoxShadow(
                  color: Color(0x331D4ED8),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Center(
            child: isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Text(
                    'Apply Changes',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
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
        color: _kBlue3,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Section label with accent bar
          Row(
            children: <Widget>[
              Container(
                width: 3,
                height: 14,
                decoration: const BoxDecoration(
                  color: _kBlue1,
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'MODEL',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: _kMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Icon(
                ready ? Icons.check_circle : Icons.downloading,
                color: ready
                    ? const Color(0xFF065F46)
                    : _kBlue1,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Gemma-4-E2B-it',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: _kNavy),
                    ),
                    Text(
                      ready
                          ? '${_fmt(_sizeBytes)} · LiteRT-LM format'
                          : _sizeBytes > 0
                              ? '${_fmt(_sizeBytes)} downloaded (incomplete)'
                              : 'Not downloaded',
                      style:
                          const TextStyle(fontSize: 12, color: _kSlate),
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
                final bool initialized =
                    widget.visionService.isInitialized.value;
                return Row(
                  children: <Widget>[
                    Icon(
                      initialized ? Icons.bolt : Icons.hourglass_empty,
                      size: 16,
                      color: initialized
                          ? const Color(0xFF065F46)
                          : const Color(0xFF92400E),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      initialized
                          ? 'Engine running'
                          : 'Engine not loaded',
                      style:
                          const TextStyle(fontSize: 12, color: _kSlate),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
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
                              onPressed: () =>
                                  Navigator.pop(context, false),
                              child: const Text('Cancel')),
                          TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, true),
                              child: const Text('Delete',
                                  style: TextStyle(
                                      color: Color(0xFF991B1B)))),
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
                  color: Color(0xFF991B1B), size: 18),
              label: const Text('Delete model file',
                  style: TextStyle(color: Color(0xFF991B1B))),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFF87171)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
