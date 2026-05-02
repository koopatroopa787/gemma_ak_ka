import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DbService {
  static Database? _db;

  static Future<Database> getDb() async {
    _db ??= await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'pharos.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE scan_results (
            id TEXT PRIMARY KEY,
            timestamp TEXT NOT NULL,
            location TEXT,
            medicine_name TEXT,
            batch_code TEXT,
            expiry_date TEXT,
            risk_score INTEGER,
            risk_level TEXT,
            flags_json TEXT,
            full_result_json TEXT,
            synced INTEGER DEFAULT 0,
            sync_queued_at TEXT,
            signature TEXT,
            public_key TEXT
          )
        ''');
      },
    );
  }

  static Future<void> saveScan({
    required String id,
    required String timestamp,
    String? location,
    String? medicineName,
    String? batchCode,
    String? expiryDate,
    required int riskScore,
    required String riskLevel,
    required List<String> flags,
    required Map<String, dynamic> fullResult,
    String? signature,
    String? publicKey,
  }) async {
    final db = await getDb();
    await db.insert(
      'scan_results',
      {
        'id': id,
        'timestamp': timestamp,
        'location': location,
        'medicine_name': medicineName,
        'batch_code': batchCode,
        'expiry_date': expiryDate,
        'risk_score': riskScore,
        'risk_level': riskLevel,
        'flags_json': jsonEncode(flags),
        'full_result_json': jsonEncode(fullResult),
        'synced': 0,
        'signature': signature,
        'public_key': publicKey,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getHistory() async {
    final db = await getDb();
    return db.query('scan_results', orderBy: 'timestamp DESC');
  }

  static Future<List<Map<String, dynamic>>> getPendingScans() async {
    final db = await getDb();
    return db.query('scan_results', where: 'synced = 0');
  }

  static Future<void> markSynced(String id) async {
    final db = await getDb();
    await db.update(
      'scan_results',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> deleteScan(String id) async {
    final db = await getDb();
    await db.delete('scan_results', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> clear() async {
    final db = await getDb();
    await db.delete('scan_results');
  }
}
