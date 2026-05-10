import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/db_service.dart';

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

      if (!mounted) {
        return;
      }
      setState(() {
        _stats = stats;
        _alerts = recentAlerts;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
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
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _stats == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF93000A)),
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
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
        children: <Widget>[
          const Text(
            'System Analytics',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: Color(0xFF191C1E),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Real-time pharmaceutical verification data.',
            style: TextStyle(color: Color(0xFF575F6B)),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.35,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            children: <Widget>[
              _statCard(
                title: 'Total',
                value: '${_intStat('total_scans')}',
                icon: Icons.inventory_2_outlined,
                accent: const Color(0xFF0053A6),
                subtitle: 'Total scans',
              ),
              _statCard(
                title: 'Critical',
                value: '$criticalCount',
                icon: Icons.warning_amber_rounded,
                accent: const Color(0xFFB71C1C),
                subtitle: 'Immediate action',
              ),
              _statCard(
                title: 'High Risk',
                value: '$highCount',
                icon: Icons.priority_high_rounded,
                accent: const Color(0xFFE65100),
                subtitle: 'Awaiting verification',
              ),
              _statCard(
                title: 'Today',
                value: '${_intStat('last_24h_count')}',
                icon: Icons.today_outlined,
                accent: const Color(0xFF0053A6),
                subtitle: 'Last 24 hours',
              ),
            ],
          ),
          const SizedBox(height: 14),
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
                const Text(
                  'Risk Distribution',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF191C1E),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 220,
                  child: Center(
                    child: _DonutChart(
                      values: <int>[criticalCount, highCount, moderateCount, lowCount],
                      colors: const <Color>[
                        Color(0xFFB71C1C),
                        Color(0xFFE65100),
                        Color(0xFFF57F17),
                        Color(0xFF2E7D32),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: <Widget>[
                    _LegendItem(label: 'Critical', color: Color(0xFFB71C1C)),
                    _LegendItem(label: 'High', color: Color(0xFFE65100)),
                    _LegendItem(label: 'Moderate', color: Color(0xFFF57F17)),
                    _LegendItem(label: 'Low', color: Color(0xFF2E7D32)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFC2C6D4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.warning_amber_rounded, color: Color(0xFFB71C1C)),
                      SizedBox(width: 8),
                      Text(
                        'Recent Alerts',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF191C1E),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (_alerts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No critical alerts found.'),
                  ),
                ..._alerts.map((Map<String, dynamic> alert) {
                  return ListTile(
                    leading: Container(
                      width: 4,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFB71C1C),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    title: Text('Batch #${alert['batch_code'] ?? 'N/A'}'),
                    subtitle: Text(
                      '${alert['medicine_name'] ?? 'Unknown'} • ${alert['timestamp'] ?? ''}',
                    ),
                    trailing: const Icon(Icons.visibility_outlined, color: Color(0xFF0053A6)),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accent,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFC2C6D4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Icon(icon, color: accent),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF575F6B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: Color(0xFF191C1E),
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: Color(0xFF727784)),
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
        Text(label),
      ],
    );
  }
}

class _DonutChart extends StatelessWidget {
  const _DonutChart({required this.values, required this.colors});

  final List<int> values;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final int total = values.fold<int>(0, (int sum, int value) => sum + value);
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
                ),
              ),
              const Text(
                'SCANS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF575F6B),
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
    final int total = values.fold<int>(0, (int sum, int value) => sum + value);
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = math.min(size.width, size.height) / 2 - 8;
    const double strokeWidth = 22;

    final Paint bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = const Color(0xFFECEEF0);
    canvas.drawCircle(center, radius, bgPaint);

    if (total == 0) {
      return;
    }

    double start = -math.pi / 2;
    for (int i = 0; i < values.length; i++) {
      final int value = values[i];
      if (value <= 0) {
        continue;
      }
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
