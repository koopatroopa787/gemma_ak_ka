// ── FILE: lib/screens/history_screen.dart ──
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/db_service.dart';
import 'result_screen.dart';

// ── Design tokens ─────────────────────────────────────────────────────────
const Color _kSurface = Color(0xFFFFFFFF);
const Color _kNavy    = Color(0xFF0B1629);
const Color _kSlate   = Color(0xFF475569);
const Color _kMuted   = Color(0xFF94A3B8);
const Color _kBorder  = Color(0xFFE2E8F0);
const Color _kBlue1   = Color(0xFF1D4ED8);
const Color _kBlue3   = Color(0xFFEFF6FF);

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const int _pageSize = 20;
  static const List<String> _filters = <String>[
    'ALL', 'LOW', 'MODERATE', 'HIGH', 'CRITICAL'
  ];

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;

  final List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  String _activeFilter = 'ALL';
  String _search = '';
  int _total = 0;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_loadHistory(reset: true));
  }

  Future<void> _loadHistory({required bool reset}) async {
    if (_isLoading || _isLoadingMore) return;

    if (reset) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final List<Map<String, dynamic>> allRows =
          await DbService.getHistoryFiltered(
        riskLevel: _activeFilter == 'ALL' ? null : _activeFilter,
        search: _search.isEmpty ? null : _search,
      );

      // Decode flags_json → List<String> so cards can render flags inline.
      final List<Map<String, dynamic>> parsedItems =
          allRows.map((Map<String, dynamic> row) {
        dynamic flags;
        try {
          flags = jsonDecode(row['flags_json'] as String? ?? '[]');
        } catch (_) {
          flags = <dynamic>[];
        }
        return <String, dynamic>{...row, 'flags': flags};
      }).toList();

      final int total = parsedItems.length;
      final int offset = reset ? 0 : _items.length;
      final List<Map<String, dynamic>> page = parsedItems.length > offset
          ? parsedItems.sublist(
              offset,
              (offset + _pageSize).clamp(0, parsedItems.length),
            )
          : <Map<String, dynamic>>[];

      if (!mounted) return;

      setState(() {
        _total = total;
        if (reset) {
          _items
            ..clear()
            ..addAll(page);
        } else {
          _items.addAll(page);
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoading || _isLoadingMore) return;
    final bool reachedEnd = _scrollController.position.pixels >=
        (_scrollController.position.maxScrollExtent - 120);
    if (reachedEnd && _items.length < _total) {
      unawaited(_loadHistory(reset: false));
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _search = value.trim();
      });
      unawaited(_loadHistory(reset: true));
    });
  }

  /// Returns risk-level palette colors for a given risk string.
  ({Color text, Color bg, Color border}) _riskPalette(String riskLevel) {
    switch (riskLevel) {
      case 'LOW':
        return (
          text: const Color(0xFF065F46),
          bg: const Color(0xFFECFDF5),
          border: const Color(0xFF6EE7B7),
        );
      case 'MODERATE':
        return (
          text: const Color(0xFF92400E),
          bg: const Color(0xFFFFFBEB),
          border: const Color(0xFFFCD34D),
        );
      case 'HIGH':
        return (
          text: const Color(0xFF9A3412),
          bg: const Color(0xFFFFF7ED),
          border: const Color(0xFFFB923C),
        );
      case 'CRITICAL':
        return (
          text: const Color(0xFF991B1B),
          bg: const Color(0xFFFEF2F2),
          border: const Color(0xFFF87171),
        );
      default:
        return (
          text: _kMuted,
          bg: const Color(0xFFF1F5F9),
          border: _kBorder,
        );
    }
  }

  String _riskInitial(String riskLevel) {
    switch (riskLevel) {
      case 'LOW':      return 'L';
      case 'MODERATE': return 'M';
      case 'HIGH':     return 'H';
      case 'CRITICAL': return 'C';
      default:         return '?';
    }
  }

  Future<void> _onRefresh() => _loadHistory(reset: true);

  void _openResult(Map<String, dynamic> item) {
    final Map<String, dynamic> normalizedResult = <String, dynamic>{
      'medicine_name': item['medicine_name'],
      'batch_code': <String, dynamic>{'extracted': item['batch_code'] ?? ''},
      'expiry_date': <String, dynamic>{'extracted': ''},
      'manufacturer': <String, dynamic>{'extracted': ''},
      'security': <String, dynamic>{'seal_intact': null},
      'risk_score': item['risk_score'],
      'risk_level': item['risk_level'],
      'flags': item['flags'] is List
          ? List<dynamic>.from(item['flags'] as List<dynamic>)
          : <dynamic>[],
      'confidence': 0.0,
      'analysis_notes': 'Loaded from history record.',
      'image_quality_ok': true,
      'timestamp': item['timestamp'],
    };

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ResultScreen(
          result: normalizedResult,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: _kBlue1));
    }

    if (_error != null && _items.isEmpty) {
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

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: _kBlue1,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
        children: <Widget>[
          // ── Page header ──────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              const Expanded(
                child: Text(
                  'History',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: _kNavy,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: _kBlue3,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$_total scans',
                  style: const TextStyle(
                    color: _kBlue1,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Search field ─────────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.all(Radius.circular(12)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 16,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search medicine or batch...',
                hintStyle: TextStyle(color: _kMuted, fontSize: 14),
                prefixIcon: Icon(Icons.search, color: _kBlue1, size: 20),
                filled: true,
                fillColor: _kSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Filter chips ─────────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filters.map((String filter) {
                final bool active = _activeFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _activeFilter = filter);
                      unawaited(_loadHistory(reset: true));
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: active ? _kBlue1 : _kSurface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: active ? _kBlue1 : _kBorder,
                        ),
                      ),
                      child: Text(
                        filter == 'ALL' ? 'All' : filter,
                        style: TextStyle(
                          color: active ? Colors.white : _kSlate,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          // ── Items ─────────────────────────────────────────────────────────
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No scans found.',
                  style: TextStyle(color: _kMuted),
                ),
              ),
            ),
          ..._items.map((Map<String, dynamic> item) {
            final String riskLevel =
                (item['risk_level'] as String?) ?? 'UNKNOWN';
            final palette = _riskPalette(riskLevel);
            final String medicine =
                (item['medicine_name'] as String?) ?? 'Unknown medicine';
            final String batchCode =
                (item['batch_code'] as String?) ?? 'N/A';
            final int riskScore =
                (item['risk_score'] as num?)?.toInt() ?? 0;
            final String initial = _riskInitial(riskLevel);
            final String timestamp =
                (item['timestamp'] as String? ?? '').split('T').first;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 16,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _openResult(item),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: <Widget>[
                      // Left: risk initial letter in colored circle
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: palette.bg,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: palette.border, width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: TextStyle(
                              color: palette.text,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Center: medicine name, batch, timestamp
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              medicine,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: _kNavy,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Batch: $batchCode',
                              style: const TextStyle(
                                  color: _kMuted, fontSize: 12),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              timestamp,
                              style: const TextStyle(
                                  color: _kMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Right: risk score badge + chevron
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: palette.bg,
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: palette.border),
                            ),
                            child: Text(
                              '$riskScore%',
                              style: TextStyle(
                                color: palette.text,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Icon(Icons.chevron_right,
                              color: _kMuted, size: 18),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          // ── Load more ─────────────────────────────────────────────────────
          if (_isLoadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                  child: CircularProgressIndicator(color: _kBlue1)),
            ),
          if (!_isLoadingMore &&
              _items.length < _total &&
              _items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                onPressed: () => unawaited(_loadHistory(reset: false)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kBlue1,
                  side: const BorderSide(color: _kBorder),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Load more'),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
