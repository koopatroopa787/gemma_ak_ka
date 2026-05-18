// ── FILE: lib/screens/result_screen.dart ──
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

// ── Design tokens ─────────────────────────────────────────────────────────
const Color _kBg      = Color(0xFFF0F4FA);
const Color _kSurface = Color(0xFFFFFFFF);
const Color _kNavy    = Color(0xFF0B1629);
const Color _kSlate   = Color(0xFF475569);
const Color _kMuted   = Color(0xFF94A3B8);
const Color _kBlue1   = Color(0xFF1D4ED8);
const Color _kBlue3   = Color(0xFFEFF6FF);

// ── Risk palette ──────────────────────────────────────────────────────────
class _RiskPalette {
  const _RiskPalette({
    required this.text,
    required this.bg,
    required this.border,
    required this.gradientEnd,
    required this.label,
  });
  final Color text;
  final Color bg;
  final Color border;
  final Color gradientEnd;
  final String label;
}

const Map<String, _RiskPalette> _riskPalette = <String, _RiskPalette>{
  'LOW': _RiskPalette(
    text: Color(0xFF065F46),
    bg: Color(0xFFECFDF5),
    border: Color(0xFF6EE7B7),
    gradientEnd: Color(0xFF059669),
    label: 'Low Risk',
  ),
  'MODERATE': _RiskPalette(
    text: Color(0xFF92400E),
    bg: Color(0xFFFFFBEB),
    border: Color(0xFFFCD34D),
    gradientEnd: Color(0xFFD97706),
    label: 'Moderate',
  ),
  'HIGH': _RiskPalette(
    text: Color(0xFF9A3412),
    bg: Color(0xFFFFF7ED),
    border: Color(0xFFFB923C),
    gradientEnd: Color(0xFFEA580C),
    label: 'High Risk',
  ),
  'CRITICAL': _RiskPalette(
    text: Color(0xFF991B1B),
    bg: Color(0xFFFEF2F2),
    border: Color(0xFFF87171),
    gradientEnd: Color(0xFFDC2626),
    label: 'Critical',
  ),
};

const Map<String, String> _flagLabels = <String, String>{
  'BATCH_FORMAT_INVALID': 'Invalid batch code format',
  'KNOWN_COUNTERFEIT_ALERT': 'Known counterfeit — WHO alert',
  'EXPIRY_DATE_MISSING': 'Expiry date not visible',
  'HOLOGRAM_MISSING': 'Security hologram absent',
  'MANUFACTURER_UNRECOGNIZED': 'Unrecognized manufacturer',
};

class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.result,
    this.imagePath,
  });

  final Map<String, dynamic> result;
  final String? imagePath;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  bool _saved = false;

  String get _riskLevel =>
      (widget.result['risk_level'] as String?)?.toUpperCase() ?? 'MODERATE';

  int get _riskScore {
    final dynamic score = widget.result['risk_score'];
    if (score is int) return score.clamp(0, 100);
    if (score is num) return score.round().clamp(0, 100);
    return 50;
  }

  double get _confidence {
    final dynamic confidence = widget.result['confidence'];
    if (confidence is num) return confidence.clamp(0, 1).toDouble();
    return 0.0;
  }

  String _nestedText(String key, {String nested = 'extracted'}) {
    final dynamic value = widget.result[key];
    if (value is Map<String, dynamic>) {
      final dynamic nestedValue = value[nested];
      if (nestedValue is String && nestedValue.isNotEmpty) return nestedValue;
    }
    if (value is String && value.isNotEmpty) return value;
    return 'N/A';
  }

  List<String> _flags() {
    final dynamic value = widget.result['flags'];
    if (value is List) {
      return value.map((dynamic item) => item.toString()).toList();
    }
    return <String>[];
  }

  bool? _sealIntact() {
    final dynamic security = widget.result['security'];
    if (security is Map<String, dynamic>) {
      return security['seal_intact'] as bool?;
    }
    return null;
  }

  // The scan is already saved to local SQLite by ScannerScreen before
  // navigating here, so this just acknowledges that to the user.
  void _saveToHistory() {
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✓ Scan saved to local history')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final _RiskPalette palette =
        _riskPalette[_riskLevel] ?? _riskPalette['MODERATE']!;
    final List<String> flags = _flags();

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ── Header ────────────────────────────────────────────────────
              _buildHeader(palette),
              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // ── Critical banner ────────────────────────────────────
                    if (_riskLevel == 'CRITICAL') ...<Widget>[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF991B1B),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '⚠ CRITICAL: Known counterfeit batch. Do NOT dispense. Quarantine immediately.',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── Flags ──────────────────────────────────────────────
                    if (flags.isNotEmpty) ...<Widget>[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: flags.map((String flag) {
                            return Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: palette.bg,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: palette.border),
                              ),
                              child: Text(
                                _flagLabels[flag] ??
                                    flag.replaceAll('_', ' '),
                                style: TextStyle(
                                  color: palette.text,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // ── Detail card ────────────────────────────────────────
                    _buildDetailCard(),
                    const SizedBox(height: 12),

                    // ── AI notes card ──────────────────────────────────────
                    _buildAiNotesCard(),

                    // ── Captured photo ─────────────────────────────────────
                    if (widget.imagePath != null) ...<Widget>[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(widget.imagePath!),
                          height: 190,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // ── Scan Another ───────────────────────────────────────
                    _GradientButton(
                      label: 'Scan Another',
                      icon: Icons.qr_code_scanner,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(height: 10),

                    // ── Save to History ────────────────────────────────────
                    OutlinedButton.icon(
                      onPressed: _saved ? null : _saveToHistory,
                      icon: const Icon(Icons.history),
                      label: Text(
                          _saved ? '✓ Saved to History' : 'Save to History'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kBlue1,
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helper widgets ────────────────────────────────────────────────────────

  Widget _buildHeader(_RiskPalette palette) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[palette.text, palette.gradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.arrow_back,
                  color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'VERIFICATION RESULT',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${palette.label.toUpperCase()} RISK',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              _RiskGauge(score: _riskScore),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'CONFIDENCE',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(_confidence * 100).round()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: _confidence,
                        minHeight: 8,
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.25),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailCard() {
    final String sealText = _sealIntact() == true
        ? 'Intact ✓'
        : _sealIntact() == false
            ? 'Compromised ⚠'
            : 'Not assessed';

    return Container(
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _DetailRow(
            label: 'Medicine Name',
            value: widget.result['medicine_name']?.toString() ?? 'N/A',
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                  child: _DetailRow(
                      label: 'Batch Code',
                      value: _nestedText('batch_code'))),
              const SizedBox(width: 16),
              Expanded(
                  child: _DetailRow(
                      label: 'Expiry',
                      value: _nestedText('expiry_date'))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                  child: _DetailRow(
                      label: 'Manufacturer',
                      value: _nestedText('manufacturer'))),
              const SizedBox(width: 16),
              Expanded(
                  child: _DetailRow(label: 'Seal', value: sealText)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAiNotesCard() {
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
          const Row(
            children: <Widget>[
              Icon(Icons.auto_awesome, size: 16, color: _kBlue1),
              SizedBox(width: 6),
              Text(
                'Gemma AI',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _kBlue1,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.result['analysis_notes']?.toString() ??
                'No notes available.',
            style: const TextStyle(
              color: _kSlate,
              fontStyle: FontStyle.italic,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared helper widgets ─────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: _kMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: _kNavy,
          ),
        ),
      ],
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF1D4ED8), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RiskGauge extends StatelessWidget {
  const _RiskGauge({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      height: 90,
      child: CustomPaint(
        painter: _RiskGaugePainter(progress: score / 100),
        child: Center(
          child: Text(
            '$score',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _RiskGaugePainter extends CustomPainter {
  const _RiskGaugePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..color = Colors.white.withValues(alpha: 0.25);

    final Paint fgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;

    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = math.min(size.width, size.height) / 2 - 7;

    canvas.drawCircle(center, radius, bgPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      (2 * math.pi) * progress,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RiskGaugePainter oldDelegate) =>
      progress != oldDelegate.progress;
}
