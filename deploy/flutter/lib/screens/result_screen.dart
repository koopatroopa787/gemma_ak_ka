import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

const Map<String, ({Color text, Color bg, String label})> _riskColors =
    <String, ({Color text, Color bg, String label})>{
  'LOW': (text: Color(0xFF2E7D32), bg: Color(0xFFE8F5E9), label: 'Low Risk'),
  'MODERATE': (text: Color(0xFFF57F17), bg: Color(0xFFFFF8E1), label: 'Moderate'),
  'HIGH': (text: Color(0xFFE65100), bg: Color(0xFFFFF3E0), label: 'High Risk'),
  'CRITICAL': (text: Color(0xFFB71C1C), bg: Color(0xFFFFEBEE), label: 'Critical'),
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

  String get _riskLevel => (widget.result['risk_level'] as String?)?.toUpperCase() ?? 'MODERATE';

  int get _riskScore {
    final dynamic score = widget.result['risk_score'];
    if (score is int) {
      return score.clamp(0, 100);
    }
    if (score is num) {
      return score.round().clamp(0, 100);
    }
    return 50;
  }

  double get _confidence {
    final dynamic confidence = widget.result['confidence'];
    if (confidence is num) {
      return confidence.clamp(0, 1).toDouble();
    }
    return 0.0;
  }

  String _nestedText(String key, {String nested = 'extracted'}) {
    final dynamic value = widget.result[key];
    if (value is Map<String, dynamic>) {
      final dynamic nestedValue = value[nested];
      if (nestedValue is String && nestedValue.isNotEmpty) {
        return nestedValue;
      }
    }
    if (value is String && value.isNotEmpty) {
      return value;
    }
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
    final ({Color text, Color bg, String label}) riskStyle = _riskColors[_riskLevel] ?? _riskColors['MODERATE']!;
    final List<String> flags = _flags();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: const Text('Verification Result'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_riskLevel == 'CRITICAL')
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB71C1C),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '⚠ CRITICAL: Known counterfeit batch. Do NOT dispense. Quarantine immediately.',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFC2C6D4)),
                ),
                child: Column(
                  children: <Widget>[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: riskStyle.text,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'VERIFICATION RESULT',
                            style: TextStyle(
                              color: Colors.white70,
                              letterSpacing: 1.2,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$_riskLevel RISK',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: <Widget>[
                          _RiskGauge(score: _riskScore, color: riskStyle.text),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const Text(
                                  'CONFIDENCE',
                                  style: TextStyle(
                                    color: Color(0xFF727784),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${(_confidence * 100).round()}% Accuracy',
                                  style: const TextStyle(
                                    color: Color(0xFF0053A6),
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: _confidence,
                                    minHeight: 6,
                                    backgroundColor: const Color(0xFFECEEF0),
                                    color: const Color(0xFF0053A6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ...flags.map(
                (String flag) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFDAD6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBA1A1A).withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    _flagLabels[flag] ?? flag.replaceAll('_', ' '),
                    style: const TextStyle(
                      color: Color(0xFF93000A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              _detailCard('Medicine Name', widget.result['medicine_name']?.toString() ?? 'N/A'),
              Row(
                children: <Widget>[
                  Expanded(child: _detailCard('Batch Code', _nestedText('batch_code'))),
                  const SizedBox(width: 8),
                  Expanded(child: _detailCard('Expiry', _nestedText('expiry_date'))),
                ],
              ),
              Row(
                children: <Widget>[
                  Expanded(child: _detailCard('Manufacturer', _nestedText('manufacturer'))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _detailCard(
                      'Seal',
                      _sealIntact() == true
                          ? 'Intact ✓'
                          : _sealIntact() == false
                              ? 'Compromised ⚠'
                              : 'Not assessed',
                    ),
                  ),
                ],
              ),
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F4F6),
                  border: Border.all(color: const Color(0xFFC2C6D4)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Gemma AI Insight',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: Color(0xFF575F6B),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.result['analysis_notes']?.toString() ?? 'No notes available.',
                      style: const TextStyle(
                        color: Color(0xFF424752),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
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
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan Another'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A6BCC),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saved ? null : _saveToHistory,
                icon: const Icon(Icons.history),
                label: Text(_saved ? '✓ Saved to History' : 'Save to History'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: const Color(0xFF1A6BCC),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailCard(String title, String value) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
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
              letterSpacing: 1,
              color: Color(0xFF727784),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF191C1E),
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskGauge extends StatelessWidget {
  const _RiskGauge({required this.score, required this.color});

  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      height: 110,
      child: CustomPaint(
        painter: _RiskGaugePainter(
          progress: score / 100,
          color: color,
        ),
        child: Center(
          child: Text(
            '$score',
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: Color(0xFF191C1E),
            ),
          ),
        ),
      ),
    );
  }
}

class _RiskGaugePainter extends CustomPainter {
  _RiskGaugePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = const Color(0xFFECEEF0);

    final Paint fgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = color;

    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = math.min(size.width, size.height) / 2 - 8;

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
  bool shouldRepaint(covariant _RiskGaugePainter oldDelegate) {
    return progress != oldDelegate.progress || color != oldDelegate.color;
  }
}
