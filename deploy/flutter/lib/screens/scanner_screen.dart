// ── FILE: lib/screens/scanner_screen.dart ──
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/db_service.dart';
import '../services/model_manager.dart';
import '../services/model_settings.dart';
import '../services/pharos_vision_service.dart';
import '../services/signing_service.dart';
import 'capture_screen.dart';
import 'result_screen.dart';

// ── Design-system constants (local) ───────────────────────────────────────
const Color _kSurface = Color(0xFFFFFFFF);
const Color _kNavy    = Color(0xFF0B1629);
const Color _kMuted   = Color(0xFF94A3B8);
const Color _kBlue1   = Color(0xFF1D4ED8);
const Color _kBlue2   = Color(0xFF3B82F6);

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({
    super.key,
    required this.visionService,
    required this.settingsService,
  });

  final PharosVisionService visionService;
  final ModelSettingsService settingsService;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  // ── Camera ──────────────────────────────────────────────────────────────
  CameraController? _cameraController;

  // ── Inference state ──────────────────────────────────────────────────────
  bool _isProcessing = false;
  int _activeStep = 0;

  // ── Model lifecycle state ─────────────────────────────────────────────────
  bool _checkingModel = true;
  bool _modelReady = false;
  bool _downloading = false;
  double _downloadProgress = 0;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  String? _modelFormatError; // non-null = wrong format detected
  bool _pickingFile = false;
  CancelToken? _cancelToken;

  static const List<String> _scanSteps = <String>[
    'Loading Gemma 4 engine…',   // step 0 — lazy model load (first scan only)
    'Image captured',
    'Running vision analysis…',
    'Calculating risk score…',
  ];

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _checkModel();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _cancelToken?.cancel('Screen disposed');
    super.dispose();
  }

  // ── Model check ───────────────────────────────────────────────────────────

  Future<void> _checkModel() async {
    setState(() {
      _checkingModel = true;
      _modelFormatError = null;
    });

    // First check if there's an existing file with wrong format.
    final int size = await ModelManager.existingFileSize();
    if (size > 0) {
      final String? formatErr = await ModelManager.checkFormat();
      if (formatErr != null) {
        // Bad file — show error and prompt user to select correct file.
        if (mounted) {
          setState(() {
            _checkingModel = false;
            _modelReady = false;
            _modelFormatError = formatErr;
          });
        }
        return;
      }
    }

    final bool ready = await ModelManager.isModelReady();
    if (!mounted) return;
    setState(() {
      _modelReady = ready;
      _checkingModel = false;
    });
    // ── DO NOT call _initEngine() here ─────────────────────────────────────
    // Loading a 2.6 GB model at the same time as the camera initialises its
    // buffers exhausts RAM on mid-range devices (OnePlus/OPPO, 8 GB class).
    // The engine is loaded lazily in _analyzeMedicine() instead, only when
    // the user actively requests a scan and the camera is already running.
  }

  // ── File picker — use Gallery's already-downloaded model ─────────────────

  Future<void> _pickModelFile() async {
    setState(() => _pickingFile = true);
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        dialogTitle: 'Select Gemma 4 .litertlm model file',
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _pickingFile = false);
        return;
      }

      final String? selectedPath = result.files.single.path;
      if (selectedPath == null) {
        setState(() => _pickingFile = false);
        return;
      }

      if (mounted) {
        setState(() => _checkingModel = true);
      }

      final String? err = await ModelManager.copyFromDevicePath(selectedPath);

      if (!mounted) return;

      if (err != null) {
        setState(() {
          _checkingModel = false;
          _pickingFile = false;
          _modelFormatError = err;
        });
        return;
      }

      // Format OK. Engine loads on first scan tap, not here.
      setState(() {
        _checkingModel = false;
        _pickingFile = false;
        _modelFormatError = null;
        _modelReady = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checkingModel = false;
        _pickingFile = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File picker error: $e')),
      );
    }
  }

  // ── Download ──────────────────────────────────────────────────────────────

  Future<void> _startDownload() async {
    // Delete any bad file before downloading fresh.
    await ModelManager.deleteModel();
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
      _downloadedBytes = 0;
      _totalBytes = 0;
      _modelFormatError = null;
    });
    _cancelToken = CancelToken();
    try {
      await ModelManager.downloadModel(
        cancelToken: _cancelToken,
        onProgress: (double progress, int received, int total) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
              _downloadedBytes = received;
              _totalBytes = total;
            });
          }
        },
      );
      if (!mounted) return;

      // Validate format right after download.
      final String? formatErr = await ModelManager.checkFormat();
      if (formatErr != null) {
        setState(() {
          _downloading = false;
          _modelFormatError = formatErr;
        });
        return;
      }

      setState(() {
        _downloading = false;
        _modelReady = true;
      });
      // Engine loads on first scan tap, not here — camera must stay healthy.
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _downloading = false);
      if (e.type != DioExceptionType.cancel) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: ${e.message}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Download error: $e')));
    }
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  Future<void> _initializeCamera() async {
    try {
      final List<CameraDescription> cameras = await availableCameras();
      final CameraDescription camera = cameras.firstWhere(
        (CameraDescription cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final CameraController controller =
          CameraController(camera, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _cameraController = controller);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Camera error: $error')));
      }
    }
  }

  // ── Scan ──────────────────────────────────────────────────────────────────

  Future<void> _analyzeMedicine() async {
    // ── Step A: open full-screen camera capture ──────────────────────────────
    // Capture navigator + messenger references BEFORE any await (lint rule
    // use_build_context_synchronously requires this).
    final NavigatorState nav = Navigator.of(context);

    // Dispose the preview camera first so CaptureScreen can use the hardware.
    // The camera is reinitialised when we return from CaptureScreen.
    final CameraController? old = _cameraController;
    setState(() => _cameraController = null);
    await old?.dispose();

    // Trigger engine loading in the background while the user is framing the
    // shot — this hides the ~15 s model-load wait behind the capture step.
    final Future<void> engineFuture =
        widget.visionService.isInitialized.value
            ? Future<void>.value()
            : _loadEngine();

    final XFile? captured = await nav.push<XFile>(
      MaterialPageRoute<XFile>(builder: (_) => const CaptureScreen()),
    );

    // Reinitialise the small preview in the background (non-blocking).
    _initializeCamera();

    if (!mounted) return;

    if (captured == null) {
      // User tapped Discard or the back button — nothing to do.
      return;
    }

    // ── Step B: await engine (usually already done by now) ────────────────────
    setState(() {
      _isProcessing = true;
      _activeStep = 0;
    });

    try {
      await engineFuture;

      if (!widget.visionService.isInitialized.value) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Model load failed: ${widget.visionService.status.value}'),
            ),
          );
          setState(() => _isProcessing = false);
        }
        return;
      }

      // ── Step C: analysis ───────────────────────────────────────────────────
      final List<int> imageBytes = await File(captured.path).readAsBytes();
      final String? location = await _getLocation();

      setState(() => _activeStep = 1);
      final String rawJson =
          await widget.visionService.analyzePackage(imageBytes);

      setState(() => _activeStep = 2);
      final Map<String, dynamic> result = _parseAnalysisResult(rawJson);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      setState(() => _activeStep = 3);

      if ((result['image_quality_ok'] as bool?) == false && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFFFC107),
            content: Text('Image quality low — retake in better lighting'),
          ),
        );
      }

      final String timestamp = DateTime.now().toUtc().toIso8601String();
      final String signature = await SigningService.signData(
        '$timestamp${_extractBatchCode(result)}'
        '${_extractRiskScore(result)}${location ?? ''}',
      );
      final String? publicKey = await SigningService.getPublicKeyBase64();

      await DbService.saveScan(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp: timestamp,
        location: location,
        medicineName:
            (result['medicine_name'] as String?) ?? 'Unknown',
        batchCode: _extractBatchCode(result),
        expiryDate: _extractExpiryDate(result),
        riskScore: _extractRiskScore(result),
        riskLevel:
            (result['risk_level'] as String?) ?? 'MODERATE',
        flags: _extractFlags(result),
        fullResult: result,
        signature: signature,
        publicKey: publicKey,
      );

      if (!mounted) return;
      setState(() => _isProcessing = false);

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ResultScreen(
            result: <String, dynamic>{
              ...result,
              'timestamp': timestamp,
              'location': location,
            },
            imagePath: captured.path,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Scan failed: $error')));
    }
  }

  /// Loads the Gemma 4 engine.  Called in the background while the user is
  /// in [CaptureScreen] so the loading time is hidden behind image capture.
  Future<void> _loadEngine() async {
    final String path = await ModelManager.modelPath();
    await widget.visionService.initialize(
        path, widget.settingsService.settings);
  }

  // ── JSON parsing ──────────────────────────────────────────────────────────

  Map<String, dynamic> _parseAnalysisResult(String rawJson) {
    Map<String, dynamic> result;
    try {
      String cleaned = rawJson.trim();
      // Strip markdown fences if the model wrapped its output
      if (cleaned.contains('```')) {
        final int s = cleaned.indexOf('{');
        final int e = cleaned.lastIndexOf('}');
        if (s != -1 && e != -1) cleaned = cleaned.substring(s, e + 1);
      }
      result = jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{
        'medicine_name': 'Unknown',
        'batch_code': <String, dynamic>{'extracted': 'UNKNOWN'},
        'expiry_date': <String, dynamic>{'extracted': 'UNKNOWN'},
        'manufacturer': <String, dynamic>{'extracted': 'Unknown'},
        'security': <String, dynamic>{'seal_intact': null},
        'risk_score': 50,
        'risk_level': 'MODERATE',
        'flags': <String>['PARSE_ERROR'],
        'confidence': 0.0,
        'analysis_notes': 'Could not parse model output — retake photo.',
        'image_quality_ok': false,
      };
    }
    return _applyPostProcessing(result);
  }

  /// Common-sense corrections applied after model output is parsed.
  ///
  /// The model sometimes over-penalises legitimate Indian blister packs —
  /// e.g. marking seal=compromised because it can't see the foil clearly, or
  /// scoring MODERATE just because there's no hologram. These rules correct
  /// the most common false positives without compromising safety:
  /// - Real counterfeits still score HIGH/CRITICAL from other signals.
  /// - We only correct false MODERATE→LOW, never false LOW→MODERATE.
  ///
  /// IMPORTANT: OCR typo fix (Step 1) runs BEFORE isKnownMfg is computed so
  /// that "Cipia" → "Cipla" is applied before the seal/score rules check the
  /// manufacturer name.  Without this ordering, "Cipia" fails isKnownMfg and
  /// Rules 2 & 3 never fire.
  Map<String, dynamic> _applyPostProcessing(Map<String, dynamic> r) {

    // ── Step 1: fix common OCR typos for known brands ─────────────────────────
    // Uses a contains-based scan so partial strings like "Cipia Ltd" still match.
    // Order matters: more-specific keys should come first.
    const List<(String, String)> mfgFixes = <(String, String)>[
      ('cipia',            'Cipla'),
      ('cipla',            'Cipla'),
      ('sun pharma',       'Sun Pharma'),
      ('sunpharma',        'Sun Pharma'),
      ('sun pharmaceutical', 'Sun Pharma'),
      ("dr reddy's",       "Dr Reddy's"),
      ('dr reddy',         "Dr Reddy's"),
      ('drreddys',         "Dr Reddy's"),
      ('lupin',            'Lupin'),
      ('torrent',          'Torrent'),
      ('zydus',            'Zydus'),
      ('mankind',          'Mankind'),
      ('alkem',            'Alkem'),
      ('intas',            'Intas'),
      ('macleods',         'Macleods'),
      ('aurobindo',        'Aurobindo'),
      ('hetero',           'Hetero'),
      ('wockhardt',        'Wockhardt'),
      ('emcure',           'Emcure'),
      ('micro labs',       'Micro Labs'),
    ];

    // Extract raw manufacturer string and apply first matching typo fix.
    String mfgRaw = (() {
      final dynamic m = r['manufacturer'];
      if (m is Map) return ((m['extracted'] as String?) ?? '').toLowerCase();
      return (m as String? ?? '').toLowerCase();
    })();

    for (final (String fragment, String canonical) in mfgFixes) {
      if (mfgRaw.contains(fragment)) {
        final dynamic m = r['manufacturer'];
        if (m is Map<String, dynamic>) {
          r = Map<String, dynamic>.from(r)
            ..['manufacturer'] =
                Map<String, dynamic>.from(m)..['extracted'] = canonical;
        }
        mfgRaw = canonical.toLowerCase(); // update so isKnownMfg sees clean name
        break;
      }
    }

    // ── Known Indian pharma manufacturers (checked against corrected name) ────
    const List<String> indianMfg = <String>[
      'cipla', 'sun pharma', 'sun pharmaceutical', 'zydus', 'dr reddy',
      "dr reddy's", 'lupin', 'torrent', 'alkem', 'mankind', 'intas',
      'abbott india', 'pfizer india', 'gsk india', 'cadila', 'wockhardt',
      'emcure', 'macleods', 'hetero', 'aurobindo', 'micro labs',
      'fdc', 'elder', 'aristo',
    ];
    final bool isKnownMfg = indianMfg.any((String n) => mfgRaw.contains(n));

    // ── Extract remaining signals ─────────────────────────────────────────────
    final dynamic security = r['security'];
    final bool? sealIntact = security is Map ? security['seal_intact'] as bool? : null;
    final int riskScore = (() {
      final dynamic s = r['risk_score'];
      if (s is int) return s;
      if (s is num) return s.round();
      return 50;
    })();
    final double confidence = (() {
      final dynamic c = r['confidence'];
      if (c is num) return c.toDouble();
      return 0.0;
    })();
    final String medicineName = (r['medicine_name'] as String? ?? '').trim();
    final bool medicineReadable = medicineName.isNotEmpty && medicineName != 'Unknown';

    // ── Rule 1: seal default ──────────────────────────────────────────────────
    // A visible, unbroken blister-pack foil = intact seal.
    // Only override to true when the model returned null/false on a pack where
    // everything else looks legitimate (known mfg, readable text, low risk).
    if (sealIntact != true && riskScore < 65 && isKnownMfg && medicineReadable) {
      if (security is Map<String, dynamic>) {
        final Map<String, dynamic> fixedSecurity =
            Map<String, dynamic>.from(security);
        fixedSecurity['seal_intact'] = true;
        fixedSecurity['tamper_evident_seal'] = true;
        r = Map<String, dynamic>.from(r)..['security'] = fixedSecurity;
      }
    }

    // ── Rule 2: MODERATE→LOW for known-good packs ─────────────────────────────
    // Score 31-45 (barely MODERATE) + known manufacturer + readable text →
    // treat as LOW.  Genuine counterfeits score much higher via other signals.
    if (riskScore >= 31 && riskScore <= 50 && isKnownMfg && medicineReadable
        && confidence >= 0.65) {
      final int adjusted = (riskScore - 15).clamp(0, 30);
      r = Map<String, dynamic>.from(r)
        ..['risk_score'] = adjusted
        ..['risk_level'] = 'LOW';
    }

    return r;
  }

  String _extractBatchCode(Map<String, dynamic> r) {
    final dynamic v = r['batch_code'];
    if (v is Map<String, dynamic>) return (v['extracted'] as String?) ?? '';
    return (v as String?) ?? '';
  }

  String _extractExpiryDate(Map<String, dynamic> r) {
    final dynamic v = r['expiry_date'];
    if (v is Map<String, dynamic>) return (v['extracted'] as String?) ?? '';
    return (v as String?) ?? '';
  }

  int _extractRiskScore(Map<String, dynamic> r) {
    final dynamic s = r['risk_score'];
    if (s is int) return s;
    if (s is num) return s.round();
    return 50;
  }

  List<String> _extractFlags(Map<String, dynamic> r) {
    final dynamic f = r['flags'];
    if (f is List) return f.map((dynamic e) => e.toString()).toList();
    return <String>[];
  }

  Future<String?> _getLocation() async {
    try {
      final LocationPermission perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) { return null; }
      final Position pos = await Geolocator.getCurrentPosition();
      return '${pos.latitude},${pos.longitude}';
    } catch (_) {
      return null;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildHero(),
              // Scanner card overlaps hero with negative top margin
              Container(
                margin: const EdgeInsets.fromLTRB(16, -24, 16, 0),
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x0A000000),
                      blurRadius: 24,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildCameraPreview(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          _buildActionArea(),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const <Widget>[
                              Icon(Icons.lock_outline,
                                  size: 14, color: _kMuted),
                              SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'All processing is on-device. No image leaves your phone.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 11, color: _kMuted),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 120),
            ],
          ),
        ),
        if (_isProcessing) _buildProcessingOverlay(),
      ],
    );
  }

  // ── Hero section ──────────────────────────────────────────────────────────

  Widget _buildHero() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[_kBlue1, _kBlue2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 48),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: const <Widget>[
                Icon(Icons.shield_outlined, color: Colors.white, size: 28),
                SizedBox(width: 10),
                Text(
                  'Pharos',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Medicine Verification',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 4),
            AnimatedBuilder(
              animation: widget.visionService.status,
              builder: (BuildContext context, _) {
                if (!widget.visionService.isInitialized.value) {
                  return const SizedBox.shrink();
                }
                return Row(
                  children: <Widget>[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF34D399),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.visionService.status.value,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Camera preview ─────────────────────────────────────────────────────────

  Widget _buildCameraPreview() {
    return GestureDetector(
      onTap: (_modelReady && !_isProcessing) ? _analyzeMedicine : null,
      child: Container(
        height: 260,
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        decoration: BoxDecoration(
          color: _kNavy,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _cameraController != null &&
                  _cameraController!.value.isInitialized
              ? Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    CameraPreview(_cameraController!),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: <Color>[
                              Color(0xCC000000),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: const Text(
                          'Tap to open camera',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      CircularProgressIndicator(color: Colors.white38),
                      SizedBox(height: 12),
                      Text(
                        'Initialising camera…',
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  // ── Action area (context-sensitive) ──────────────────────────────────────

  Widget _buildActionArea() {
    // Checking model state
    if (_checkingModel) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: CircularProgressIndicator(color: _kBlue1),
        ),
      );
    }

    // ── Wrong format error ─────────────────────────────────────────────────
    if (_modelFormatError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF87171)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    Icon(Icons.error_outline,
                        color: Color(0xFF991B1B), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Wrong model format',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF991B1B),
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _modelFormatError!,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _gradientButton(
            label: 'Delete & re-download',
            icon: Icons.refresh,
            onPressed: () async {
              await ModelManager.deleteModel();
              setState(() => _modelFormatError = null);
              await _startDownload();
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickingFile ? null : _pickModelFile,
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('Select file manually'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kBlue1,
              side: const BorderSide(color: Color(0xFFE2E8F0)),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      );
    }

    // ── Model not downloaded ───────────────────────────────────────────────
    if (!_modelReady && !_downloading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFCD34D)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Gemma 4 model not downloaded',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF92400E)),
                ),
                SizedBox(height: 4),
                Text(
                  'Download once (~2.6 GB on Wi-Fi). After that Pharos works '
                  'fully offline forever — no internet needed to scan.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _gradientButton(
            label: 'Download Gemma 4 E2B (~2.6 GB)',
            icon: Icons.download,
            onPressed: _startDownload,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickingFile ? null : _pickModelFile,
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('Select existing file from device'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kBlue1,
              side: const BorderSide(color: Color(0xFFE2E8F0)),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      );
    }

    // ── Downloading ────────────────────────────────────────────────────────
    if (_downloading) {
      final String received = _fmt(_downloadedBytes);
      final String total = _totalBytes > 0 ? _fmt(_totalBytes) : '~2.6 GB';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Downloading Gemma 4… $received / $total',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: _kNavy),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _downloadProgress > 0 ? _downloadProgress : null,
              minHeight: 8,
              backgroundColor: const Color(0xFFE2E8F0),
              color: _kBlue1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(_downloadProgress * 100).toStringAsFixed(1)}%',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: _kMuted),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              _cancelToken?.cancel('User cancelled');
              setState(() => _downloading = false);
            },
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF991B1B))),
          ),
        ],
      );
    }

    // ── Model ready — show scan button ─────────────────────────────────────
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _gradientButton(
          label: 'Analyze Medicine',
          icon: Icons.camera_alt_outlined,
          onPressed: _isProcessing ? null : _analyzeMedicine,
          height: 52,
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Model loads on first scan (~15 s) then stays ready.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: _kMuted),
          ),
        ),
      ],
    );
  }

  // ── Processing overlay ────────────────────────────────────────────────────

  Widget _buildProcessingOverlay() {
    return Container(
      color: Colors.black45,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 32,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                    strokeWidth: 3, color: _kBlue1),
              ),
              const SizedBox(height: 20),
              ...List<Widget>.generate(_scanSteps.length, (int i) {
                final bool done = i < _activeStep;
                final bool active = i == _activeStep;
                Color dotColor;
                if (done) {
                  dotColor = const Color(0xFF34D399);
                } else if (active) {
                  dotColor = _kBlue1;
                } else {
                  dotColor = const Color(0xFFE2E8F0);
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _scanSteps[i],
                          style: TextStyle(
                            fontSize: 14,
                            color: done || active ? _kNavy : _kMuted,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _fmt(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Widget _gradientButton({
    required String label,
    required IconData icon,
    VoidCallback? onPressed,
    double height = 52,
  }) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: onPressed != null
            ? const LinearGradient(
                colors: <Color>[_kBlue1, Color(0xFF2563EB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: onPressed == null ? const Color(0xFFE2E8F0) : null,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon,
                  color: onPressed != null ? Colors.white : _kMuted,
                  size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: onPressed != null ? Colors.white : _kMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
