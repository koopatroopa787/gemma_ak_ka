import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import 'db_service.dart';
import 'signing_service.dart';

const String _syncUrl = 'https://pharos-sync.onrender.com/api/v1/reports';

class SyncService {
  final isSyncing = ValueNotifier<bool>(false);
  final syncStatus = ValueNotifier<String>('');

  Future<void> syncIfOnline() async {
    final List<ConnectivityResult> connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      syncStatus.value = 'Offline';
      return;
    }

    await performSync();
  }

  Future<void> performSync() async {
    try {
      isSyncing.value = true;
      syncStatus.value = 'Syncing...';

      final pending = await DbService.getPendingScans();
      if (pending.isEmpty) {
        syncStatus.value = 'Up to date';
        isSyncing.value = false;
        return;
      }

      final publicKeyB64 = await SigningService.getPublicKeyBase64();
      if (publicKeyB64 == null) {
        throw Exception('No signing key available');
      }

      // Sign the sync payload
      final dataToSign = pending
          .map((r) => '${r['timestamp']}${r['batch_code']}${r['risk_score']}')
          .join('|');
      final signature = await SigningService.signData(dataToSign);

      // Build payload
      final payload = {
        'device_id': 'pharos-device-001', // TODO: Generate per device
        'public_key': publicKeyB64,
        'signature': signature,
        'scan_results': pending
            .map((r) => {
                  'timestamp': r['timestamp'],
                  'location': r['location'],
                  'medicine_name': r['medicine_name'],
                  'batch_code': r['batch_code'],
                  'risk_level': r['risk_level'],
                  'risk_score': r['risk_score'],
                  'flags': jsonDecode(r['flags_json'] as String? ?? '[]'),
                })
            .toList(),
      };

      // POST to server
      final response = await http.post(
        Uri.parse(_syncUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        // Mark all as synced
        for (final row in pending) {
          await DbService.markSynced(row['id']);
        }
        syncStatus.value = 'Synced ${pending.length} scans';
      } else {
        syncStatus.value = 'Sync failed: ${response.statusCode}';
      }
    } catch (e) {
      // Sync is an optional cloud feature — always fail silently so the
      // offline-first experience is never interrupted by network errors.
      debugPrint('Pharos sync skipped: $e');
      syncStatus.value = 'Sync unavailable';
    } finally {
      isSyncing.value = false;
    }
  }

  void dispose() {
    isSyncing.dispose();
    syncStatus.dispose();
  }
}
