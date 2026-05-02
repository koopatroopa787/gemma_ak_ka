import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/db_service.dart';
import '../services/sync_service.dart';
import 'result_screen.dart';

class HistoryScreen extends StatefulWidget {
  final SyncService syncService;

  const HistoryScreen({super.key, required this.syncService});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<Map<String, dynamic>>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _refreshHistory();
  }

  void _refreshHistory() {
    setState(() {
      _historyFuture = DbService.getHistory();
    });
  }

  Future<void> _pullToRefresh() async {
    _refreshHistory();
    await widget.syncService.syncIfOnline();
    await Future.delayed(const Duration(milliseconds: 500));
    _refreshHistory();
  }

  String _getSyncStatus(Map<String, dynamic> item) {
    final synced = item['synced'] as int?;
    if (synced == 1) {
      return '✅ Synced';
    }
    return '⏳ Pending';
  }

  Color _getRiskColor(String riskLevel) {
    const colors = {
      'LOW': Color(0xFF1DB85A),
      'MODERATE': Color(0xFFF5A623),
      'HIGH': Color(0xFFD0021B),
      'CRITICAL': Color(0xFF7B0000),
    };
    return colors[riskLevel] ?? Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan History'),
        actions: [
          ValueListenableBuilder(
            valueListenable: widget.syncService.isSyncing,
            builder: (context, isSyncing, _) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: isSyncing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        onPressed: _pullToRefresh,
                        icon: const Icon(Icons.sync),
                      ),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Center(
              child: Text('No scans yet. Start by scanning a package.'),
            );
          }

          return RefreshIndicator(
            onRefresh: _pullToRefresh,
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final riskLevel = item['risk_level'] as String? ?? 'UNKNOWN';
                final timestamp = DateTime.parse(item['timestamp']);
                final timeStr =
                    '${timestamp.hour}:${timestamp.minute} ${timestamp.day}/${timestamp.month}';

                return ListTile(
                  title: Text(item['medicine_name'] ?? 'Unknown Medicine'),
                  subtitle: Text(timeStr),
                  leading: CircleAvatar(
                    backgroundColor: _getRiskColor(riskLevel),
                    child: Text(
                      riskLevel[0],
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  trailing: Text(_getSyncStatus(item)),
                  onTap: () => _showDetail(context, item),
                  onLongPress: () => _showDeleteDialog(context, item),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showDetail(BuildContext context, Map<String, dynamic> item) {
    final fullResult = jsonDecode(item['full_result_json'] as String? ?? '{}');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ResultScreen(result: fullResult),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Scan?'),
        content: Text('Delete scan of ${item['medicine_name']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await DbService.deleteScan(item['id']);
              _refreshHistory();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
