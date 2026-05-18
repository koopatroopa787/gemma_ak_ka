// ── FILE: lib/screens/dashboard_screen.dart ──
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/db_service.dart';

// ── Design tokens ─────────────────────────────────────────────────────────
const Color _kSurface = Color(0xFFFFFFFF);
const Color _kNavy    = Color(0xFF0B1629);
const Color _kSlate   = Color(0xFF475569);
const Color _kMuted   = Color(0xFF94A3B8);
const Color _kBlue1   = Color(0xFF1D4ED8);

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _alerts = <Map<String, dynamic>>[];
  Timer? _refreshTimer;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshData());
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_refreshData(showLoader: false));
    });
  }

  Future<void> _refreshData({bool showLoader = true}) async {
    if (showLoader) {
      setState(() => _loading = true);
    }
    try {
      final Map<String, int> rawStats = await DbService.getStats();
      final Map<String, dynamic> stats =
          rawStats.map((String k, int v) => MapEntry<String, dynamic>(k, v));

      final List<Map<String, dynamic>> alerts =
          await DbService.getHistoryFiltered(riskLevel: 'CRITICAL');
      final List<Map<String, dynamic>> recentAlerts =
          alerts.length > 10 ? alerts.sublist(0, 10) : alerts;

      if (!mounted) return;
      setState(() {
        _stats = stats;
        _alerts = recentAlerts;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted && showLoader) {
        setState(() => _loading = false);
      }
    }
  }

  int _intStat(String key) => (_stats?[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    if (_loading && _stats == null) {
      return const Center(child: CircularProgressIndicator(color: _kBlue1));
    }
    if (_error != null && _stats == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF991B1B)),
          ),
        ),
      );
    }

    final int criticalCount = _intStat('critical_count');
    final int highCount = _intStat('high_count');
    final int moderateCount = _intStat('moderate_count');
    final int lowCount = _intStat('low_count');

    return RefreshIndicator(
      onRefresh: _refreshData,
      color: _kBlue1,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
        children: <Widget>[
          // ── Page header ──────────────────────────────────────────────────
          const Text(
            'Analytics',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: _kNavy,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Real-time pharmaceutical verification data.',
            style: TextStyle(color: _kSlate, fontSize: 14),
          ),
          const SizedBox(height: 20),

          // ── Stats grid ───────────────────────────────────────────────────
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: <Widget>[
              _StatCard(
                label: 'Total Scans',
                value: '${_intStat('total_scans')}',
                icon: Icons.inventory_2_outlined,
                borderColor: _kBlue1,
                iconColor: _kBlue1,
              ),
              _StatCard(
                label: 'Critical',
                value: '$criticalCount',
                icon: Icons.warning_amber_rounded,
                borderColor: const Color(0xFFF87171),
                iconColor: const Color(0xFF991B1B),
              ),
              _StatCard(
                label: 'High Risk',
                value: '$highCount',
                icon: Icons.priority_high_rounded,
                borderColor: const Color(0xFFFB923C),
                iconColor: const Color(0xFF9A3412),
              ),
              _StatCard(
                label: 'Today',
                value: '${_intStat('last_24h_count')}',
                icon: Icons.today_outlined,
                borderColor: const Color(0xFF818CF8),
                iconColor: const Color(0xFF4338CA),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Risk distribution card ───────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
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
                const Text(
                  'Risk Distribution',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: _kNavy,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: Center(
                    child: _DonutChart(
                      values: <int>[
                        criticalCount,
                        highCount,
                        moderateCount,
                        lowCount
                      ],
                      colors: const <Color>[
                        Color(0xFF991B1B),
                        Color(0xFF9A3412),
                        Color(0xFF92400E),
                        Color(0xFF065F46),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: <Widget>[
                    _LegendItem(label: 'Critical', color: Color(0xFF991B1B)),
                    _LegendItem(label: 'High', color: Color(0xFF9A3412)),
                    _LegendItem(label: 'Moderate', color: Color(0xFF92400E)),
                    _LegendItem(label: 'Low', color: Color(0xFF065F46)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Alerts card ──────────────────────────────────────────────────
          Container(
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
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.warning_amber_rounded,
                          color: Color(0xFF991B1B), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Recent Alerts',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: _kNavy,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                if (_alerts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No critical alerts found.',
                      style: TextStyle(color: _kMuted),
                    ),
                  ),
                ..._alerts.map((Map<String, dynamic> alert) {
                  return Container(
                    margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border(
                        left: const BorderSide(
                            color: Color(0xFFF87171), width: 3),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                (alert['medicine_name'] as String?) ??
                                    'Unknown',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _kNavy,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Batch #${alert['batch_code'] ?? 'N/A'}',
                                style: const TextStyle(
                                    color: _kSlate, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          (alert['timestamp'] as String? ?? '')
                              .split('T')
                              .first,
                          style: const TextStyle(
                              color: _kMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.borderColor,
    required this.iconColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color borderColor;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: borderColor, width: 4)),
        boxShadow: const <BoxShadow>[
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Spacer(),
              Icon(icon, color: iconColor, size: 22),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: _kNavy,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: _kMuted),
          ),
        ],
      ),
    );
  }
}

// ── Legend item ───────────────────────────────────────────────────────────

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: _kSlate, fontSize: 13)),
      ],
    );
  }
}

// ── Donut chart (preserved exactly) ──────────────────────────────────────

class _DonutChart extends StatelessWidget {
  const _DonutChart({required this.values, required this.colors});

  final List<int> values;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final int total =
        values.fold<int>(0, (int sum, int value) => sum + value);
    return SizedBox(
      width: 180,
      height: 180,
      child: CustomPaint(
        painter: _DonutPainter(values: values, colors: colors),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '$total',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: _kNavy,
                ),
              ),
              const Text(
                'SCANS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _kMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.values, required this.colors});

  final List<int> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final int total =
        values.fold<int>(0, (int sum, int value) => sum + value);
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = math.min(size.width, size.height) / 2 - 8;
    const double strokeWidth = 22;

    final Paint bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = const Color(0xFFE2E8F0);
    canvas.drawCircle(center, radius, bgPaint);

    if (total == 0) return;

    double start = -math.pi / 2;
    for (int i = 0; i < values.length; i++) {
      final int value = values[i];
      if (value <= 0) continue;
      final double sweep = (value / total) * (2 * math.pi);
      final Paint paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt
        ..color = colors[i];
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return values != oldDelegate.values || colors != oldDelegate.colors;
  }
}
