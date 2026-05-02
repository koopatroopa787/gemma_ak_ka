import 'package:flutter/material.dart';
import 'services/cactus_service.dart';
import 'services/signing_service.dart';
import 'services/sync_service.dart';
import 'screens/scanner_screen.dart';
import 'screens/history_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SigningService.generateKeypair();
  runApp(const PharosApp());
}

class PharosApp extends StatelessWidget {
  const PharosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pharos',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: ColorScheme.dark(
          primary: Colors.blue.shade400,
          surface: const Color(0xFF1E1E1E),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 16, fontFamily: 'Roboto'),
          headlineSmall: TextStyle(fontSize: 24, fontFamily: 'Roboto'),
        ),
      ),
      home: const PharosHome(),
    );
  }
}

class PharosHome extends StatefulWidget {
  const PharosHome({super.key});

  @override
  State<PharosHome> createState() => _PharosHomeState();
}

class _PharosHomeState extends State<PharosHome> {
  late final CactusService _cactusService;
  late final SyncService _syncService;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _cactusService = CactusService();
    _syncService = SyncService();
    _initServices();
  }

  Future<void> _initServices() async {
    await _cactusService.initialize();
    await _syncService.syncIfOnline();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ScannerScreen(cactusService: _cactusService),
          HistoryScreen(syncService: _syncService),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: 'Scan'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cactusService.dispose();
    _syncService.dispose();
    super.dispose();
  }
}
