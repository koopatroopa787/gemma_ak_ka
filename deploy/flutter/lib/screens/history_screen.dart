import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/db_service.dart';
import 'result_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const int _pageSize = 20;
  static const List<String> _filters = <String>['ALL', 'LOW', 'MODERATE', 'HIGH', 'CRITICAL'];

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
    if (_isLoading || _isLoadingMore) {
      return;
    }

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

      if (!mounted) {
        return;
      }

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
      if (!mounted) {
        return;
      }
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
    if (!_scrollController.hasClients || _isLoading || _isLoadingMore) {
      return;
    }
    final bool reachedEnd = _scrollController.position.pixels >=
        (_scrollController.position.maxScrollExtent - 120);
    if (reachedEnd && _items.length < _total) {
      unawaited(_loadHistory(reset: false));
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _search = value.trim();
      });
      unawaited(_loadHistory(reset: true));
    });
  }

  Color _riskColor(String riskLevel) {
    switch (riskLevel) {
      case 'LOW':
        return const Color(0xFF2E7D32);
      case 'MODERATE':
        return const Color(0xFFF57F17);
      case 'HIGH':
        return const Color(0xFFE65100);
      case 'CRITICAL':
        return const Color(0xFFB71C1C);
      default:
        return const Color(0xFF727784);
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
      'flags': item['flags'] is List ? List<dynamic>.from(item['flags'] as List<dynamic>) : <dynamic>[],
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
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _items.isEmpty) {
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

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Scan History',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF191C1E),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Review previous pharmaceutical verifications',
                      style: TextStyle(color: Color(0xFF575F6B)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAEFFF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_total TOTAL',
                  style: const TextStyle(
                    color: Color(0xFF0053A6),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search medicine or batch...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFC2C6D4)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFC2C6D4)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filters.map((String filter) {
                final bool active = _activeFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(filter == 'ALL' ? 'All' : filter),
                    selected: active,
                    onSelected: (_) {
                      setState(() => _activeFilter = filter);
                      unawaited(_loadHistory(reset: true));
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No scans found.'),
              ),
            ),
          ..._items.map((Map<String, dynamic> item) {
            final String riskLevel = (item['risk_level'] as String?) ?? 'UNKNOWN';
            final Color color = _riskColor(riskLevel);
            final String medicine = (item['medicine_name'] as String?) ?? 'Unknown medicine';
            final String batchCode = (item['batch_code'] as String?) ?? 'N/A';
            final int riskScore = (item['risk_score'] as num?)?.toInt() ?? 0;
            final List<String> flags = (item['flags'] is List)
                ? (item['flags'] as List<dynamic>).map((dynamic e) => e.toString()).toList()
                : <String>[];

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC2C6D4)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openResult(item),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 4,
                      height: 122,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    medicine,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    riskLevel,
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Batch: $batchCode',
                              style: const TextStyle(color: Color(0xFF575F6B)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${item['timestamp']} • $riskScore% risk',
                              style: const TextStyle(color: Color(0xFF727784), fontSize: 12),
                            ),
                            if (flags.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 6),
                              Text(
                                flags.join(', '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF424752),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.chevron_right, color: Color(0xFF727784)),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (_isLoadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (!_isLoadingMore && _items.length < _total && _items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                onPressed: () => unawaited(_loadHistory(reset: false)),
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
