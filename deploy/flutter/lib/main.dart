import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/dashboard_screen.dart';
import 'screens/history_screen.dart';
import 'screens/scanner_screen.dart';
import 'screens/settings_screen.dart';
import 'services/model_settings.dart';
import 'services/pharos_vision_service.dart';
import 'services/signing_service.dart';
import 'services/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ed25519 keypair — generated once, persisted in FlutterSecureStorage.
  await SigningService.generateKeypair();

  // Load persisted model settings (temperature, topK, etc.) before UI builds.
  final ModelSettingsService settingsService = ModelSettingsService();
  await settingsService.load();

  // Vision service — bridges Dart ↔ Kotlin LiteRT-LM module via MethodChannel.
  // The scanner screen handles model-ready check + download + engine init.
  final PharosVisionService visionService = PharosVisionService();

  runApp(PharosApp(
    visionService: visionService,
    settingsService: settingsService,
  ));
}

// ─────────────────────────────────────────────────────────────────────────────
class PharosApp extends StatefulWidget {
  const PharosApp({
    super.key,
    required this.visionService,
    required this.settingsService,
  });

  final PharosVisionService visionService;
  final ModelSettingsService settingsService;

  @override
  State<PharosApp> createState() => _PharosAppState();
}

class _PharosAppState extends State<PharosApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pharos',
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Inter',
        scaffoldBackgroundColor: const Color(0xFFF8F9FB),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0053A6),
          secondary: Color(0xFF575F6B),
          surface: Colors.white,
          error: Color(0xFFBA1A1A),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF191C1E),
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Inter',
      ),
      home: PharosHome(
        onToggleTheme: _toggleTheme,
        visionService: widget.visionService,
        settingsService: widget.settingsService,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class PharosHome extends StatefulWidget {
  const PharosHome({
    super.key,
    required this.onToggleTheme,
    required this.visionService,
    required this.settingsService,
  });

  final VoidCallback onToggleTheme;
  final PharosVisionService visionService;
  final ModelSettingsService settingsService;

  @override
  State<PharosHome> createState() => _PharosHomeState();
}

class _PharosHomeState extends State<PharosHome> {
  final SyncService _syncService = SyncService();
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = <Widget>[
      ScannerScreen(
        visionService: widget.visionService,
        settingsService: widget.settingsService,
      ),
      const HistoryScreen(),
      const DashboardScreen(),
      SettingsScreen(
        settingsService: widget.settingsService,
        visionService: widget.visionService,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: <Widget>[
            Icon(Icons.shield_outlined, color: Color(0xFF1A6BCC)),
            SizedBox(width: 8),
            Text(
              'Pharos',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A6BCC),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            onPressed: widget.onToggleTheme,
            icon: const Icon(Icons.dark_mode_outlined, color: Color(0xFF1A6BCC)),
            tooltip: 'Toggle theme',
          ),
        ],
      ),
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (int index) =>
            setState(() => _currentIndex = index),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.document_scanner_outlined),
            label: 'Scanner',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _syncService.dispose();
    unawaited(widget.visionService.dispose());
    super.dispose();
  }
}
