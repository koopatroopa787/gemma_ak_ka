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
import 'result_screen.dart';

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

  Future<void> _initEngine() async {
    final String path = await ModelManager.modelPath();
    try {
      await widget.visionService.initialize(path, widget.settingsService.settings);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Engine load failed: $e')),
        );
      }
    }
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
    final CameraController? controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Camera not ready')));
      return;
    }
    setState(() {
      _isProcessing = true;
      _activeStep = 0;
    });
    try {
      // ── Step 0: lazy engine load (first scan only, ~5-15 s) ──────────────
      // The camera is already running and stable at this point.
      // We load the 2.6 GB model NOW so camera and model never compete for RAM.
      if (!widget.visionService.isInitialized.value) {
        final String path = await ModelManager.modelPath();
        await widget.visionService.initialize(
            path, widget.settingsService.settings);
        if (!widget.visionService.isInitialized.value) {
          // Engine failed to load — surface the error from the status notifier.
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
      }

      final XFile imageFile = await controller.takePicture();
      final List<int> imageBytes = await File(imageFile.path).readAsBytes();
      final String? location = await _getLocation();

      setState(() => _activeStep = 1);
      final String rawJson = await widget.visionService.analyzePackage(imageBytes);

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
        '$timestamp${_extractBatchCode(result)}${_extractRiskScore(result)}${location ?? ''}',
      );
      final String? publicKey = await SigningService.getPublicKeyBase64();

      await DbService.saveScan(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp: timestamp,
        location: location,
        medicineName: (result['medicine_name'] as String?) ?? 'Unknown',
        batchCode: _extractBatchCode(result),
        expiryDate: _extractExpiryDate(result),
        riskScore: _extractRiskScore(result),
        riskLevel: (result['risk_level'] as String?) ?? 'MODERATE',
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
            imagePath: imageFile.path,
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

  // ── JSON parsing ──────────────────────────────────────────────────────────

  Map<String, dynamic> _parseAnalysisResult(String rawJson) {
    try {
      String cleaned = rawJson.trim();
      if (cleaned.startsWith('```')) {
        final int s = cleaned.indexOf('{');
        final int e = cleaned.lastIndexOf('}');
        if (s != -1 && e != -1) cleaned = cleaned.substring(s, e + 1);
      }
      return jsonDecode(cleaned) as Map<String, dynamic>;
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
          perm == LocationPermission.deniedForever) return null;
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
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  'Verify Medicine Authenticity',
                  style: TextStyle(
                    fontSize: 30,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF191C1E),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'On-device Gemma 4 AI — fully offline, no data leaves your phone.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: Color(0xFF424752),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFC2C6D4)),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      // Camera preview
                      Container(
                        height: 300,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFFC2C6D4), width: 2),
                          color: const Color(0xFFF2F4F6),
                        ),
                        child: _cameraController == null ||
                                !_cameraController!.value.isInitialized
                            ? const Center(child: CircularProgressIndicator())
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: CameraPreview(_cameraController!),
                              ),
                      ),
                      const SizedBox(height: 16),
                      _buildActionArea(),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const <Widget>[
                          Icon(Icons.lock_outline,
                              size: 16, color: Color(0xFF5D6571)),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'All processing is on-device. No image leaves your phone.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF5D6571)),
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
        ),
        if (_isProcessing) _buildProcessingOverlay(),
      ],
    );
  }

  // ── Action area (context-sensitive) ──────────────────────────────────────

  Widget _buildActionArea() {
    // Checking model state
    if (_checkingModel) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: CircularProgressIndicator(),
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
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFFB71C1C).withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    Icon(Icons.error_outline,
                        color: Color(0xFFB71C1C), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Wrong model format',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFB71C1C),
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _modelFormatError!,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF424752)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Re-download — the URL is correct, just delete the bad file first.
          ElevatedButton.icon(
            onPressed: () async {
              await ModelManager.deleteModel();
              setState(() => _modelFormatError = null);
              await _startDownload();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Delete & re-download'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A6BCC),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 8),
          // Escape hatch — advanced users who have the file elsewhere.
          OutlinedButton.icon(
            onPressed: _pickingFile ? null : _pickModelFile,
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('Select file manually'),
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
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFFF57F17).withOpacity(0.3)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Gemma 4 model not downloaded',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: Color(0xFFE65100)),
                ),
                SizedBox(height: 4),
                Text(
                  'Download once (~2.6 GB on Wi-Fi). After that Pharos works '
                  'fully offline forever — no internet needed to scan.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF424752)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Primary — auto download from HuggingFace
          ElevatedButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.download),
            label: const Text('Download Gemma 4 E2B (~2.6 GB)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A6BCC),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 8),
          // Secondary — for users who already have the file
          OutlinedButton.icon(
            onPressed: _pickingFile ? null : _pickModelFile,
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('Select existing file from device'),
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
                fontWeight: FontWeight.w600, color: Color(0xFF191C1E)),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _downloadProgress > 0 ? _downloadProgress : null,
              minHeight: 8,
              backgroundColor: const Color(0xFFECEEF0),
              color: const Color(0xFF1A6BCC),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(_downloadProgress * 100).toStringAsFixed(1)}%',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFF727784)),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              _cancelToken?.cancel('User cancelled');
              setState(() => _downloading = false);
            },
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFFB71C1C))),
          ),
        ],
      );
    }

    // ── Model ready — show scan button ─────────────────────────────────────
    // Engine is NOT loaded here — it loads lazily on first tap of Analyze.
    // This keeps the camera healthy by avoiding memory contention at startup.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ElevatedButton.icon(
          onPressed: _isProcessing ? null : _analyzeMedicine,
          icon: const Icon(Icons.analytics_outlined),
          label: const Text('Analyze Medicine'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A6BCC),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Model loads on first scan (~15 s) then stays ready.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Color(0xFF727784)),
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
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 16),
              ...List<Widget>.generate(_scanSteps.length, (int i) {
                final bool done = i < _activeStep;
                final bool active = i == _activeStep;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        done
                            ? Icons.check_circle
                            : (active
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked),
                        size: 16,
                        color: done || active
                            ? const Color(0xFF1A6BCC)
                            : const Color(0xFF727784),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _scanSteps[i],
                          style: TextStyle(
                            fontSize: 14,
                            color: done || active
                                ? const Color(0xFF191C1E)
                                : const Color(0xFF727784),
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
}
