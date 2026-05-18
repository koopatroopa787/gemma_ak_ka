// ── FILE: lib/main.dart ──
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

// ── Design-system constants ────────────────────────────────────────────────
const Color kBg      = Color(0xFFF0F4FA);
const Color kSurface = Color(0xFFFFFFFF);
const Color kNavy    = Color(0xFF0B1629);
const Color kSlate   = Color(0xFF475569);
const Color kMuted   = Color(0xFF94A3B8);
const Color kBorder  = Color(0xFFE2E8F0);
const Color kBlue1   = Color(0xFF1D4ED8);
const Color kBlue2   = Color(0xFF3B82F6);
const Color kBlue3   = Color(0xFFEFF6FF);

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
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.light(
          primary: kBlue1,
          secondary: kSlate,
          surface: kSurface,
          error: Color(0xFFBA1A1A),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kSurface,
          foregroundColor: kNavy,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: kSlate),
          bodyLarge: TextStyle(color: kNavy),
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

  static const List<_NavItem> _navItems = <_NavItem>[
    _NavItem(icon: Icons.document_scanner_outlined, label: 'Scanner'),
    _NavItem(icon: Icons.history_outlined, label: 'History'),
    _NavItem(icon: Icons.bar_chart_outlined, label: 'Analytics'),
    _NavItem(icon: Icons.tune_outlined, label: 'Settings'),
  ];

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
      backgroundColor: kBg,
      // No global AppBar — title lives inside ScannerScreen's hero section.
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: _FloatingNavBar(
        currentIndex: _currentIndex,
        items: _navItems,
        onTap: (int index) => setState(() => _currentIndex = index),
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

// ── Floating bottom nav ────────────────────────────────────────────────────

class _NavItem {
  const _NavItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  final int currentIndex;
  final List<_NavItem> items;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(40),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List<Widget>.generate(items.length, (int i) {
              final bool selected = i == currentIndex;
              final _NavItem item = items[i];
              return GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  padding: selected
                      ? const EdgeInsets.symmetric(horizontal: 18, vertical: 10)
                      : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: selected
                        ? const LinearGradient(
                            colors: <Color>[kBlue1, Color(0xFF2563EB)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        item.icon,
                        size: 22,
                        color: selected ? kSurface : kMuted,
                      ),
                      if (selected) ...<Widget>[
                        const SizedBox(width: 6),
                        Text(
                          item.label,
                          style: const TextStyle(
                            color: kSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
