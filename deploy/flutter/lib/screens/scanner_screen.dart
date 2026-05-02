import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import '../services/cactus_service.dart';
import '../services/db_service.dart';
import '../services/signing_service.dart';
import 'result_screen.dart';

const String systemPrompt = '''You are Pharos, an expert pharmaceutical packaging analyst.
Analyse the pharmaceutical blister pack in the image. Examine:
1. All printed text: batch code, expiry date, medicine name, strength, manufacturer
2. Print quality: sharpness, consistent colour, proper alignment
3. Security features: hologram, tamper seal, anti-counterfeit markings
4. Overall consistency: does everything match what you'd expect from this type of pack?

Respond ONLY with a valid JSON object. No preamble, no explanation outside JSON.
If image quality prevents analysis, set image_quality_ok: false and risk_score: 50.

You must return a JSON object with exactly these fields:
- medicine_name: string
- batch_code: {extracted, format_valid, format_error, registry_match}
- expiry_date: {extracted, format_valid, not_expired}
- manufacturer: {extracted, region_inferred, name_legible}
- security: {hologram_detected, hologram_intact, tamper_evident_seal, seal_intact}
- visual_anomalies: list of {anomaly_type, severity, region, description}
- risk_score: integer 0–100
- risk_level: one of LOW / MODERATE / HIGH / CRITICAL
- flags: list of short strings
- confidence: float 0.0–1.0
- analysis_notes: plain English summary
- image_quality_ok: boolean
''';

class ScannerScreen extends StatefulWidget {
  final CactusService cactusService;

  const ScannerScreen({super.key, required this.cactusService});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _cameraController;
  bool _isProcessing = false;
  String _processingStep = '';

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final rear = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        rear,
        ResolutionPreset.high,
      );
      await _cameraController!.initialize();
      setState(() {});
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _scanPack() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera not ready')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _processingStep = 'Reading packaging...';
    });

    try {
      // Capture image
      final image = await _cameraController!.takePicture();
      final imageBytes = await image.readAsBytes();

      // Get location
      final location = await _getLocation();

      // Run Cactus inference
      setState(() => _processingStep = 'Analyzing image...');
      final rawOutput =
          await widget.cactusService.analyzePackage(imageBytes, systemPrompt);

      // Parse result
      setState(() => _processingStep = 'Verifying batch code...');
      final parsed = _parseAnalysisOutput(rawOutput);

      // Sign result
      final signature = await SigningService.signData(
        '${DateTime.now()}${parsed['batch_code']}${parsed['risk_score']}$location',
      );
      final publicKey = await SigningService.getPublicKeyBase64();

      // Save to DB
      final scanId = DateTime.now().millisecondsSinceEpoch.toString();
      await DbService.saveScan(
        id: scanId,
        timestamp: DateTime.now().toIso8601String(),
        location: location,
        medicineName: parsed['medicine_name'],
        batchCode: parsed['batch_code'],
        expiryDate: parsed['expiry_date'],
        riskScore: parsed['risk_score'] ?? 50,
        riskLevel: parsed['risk_level'] ?? 'MODERATE',
        flags: List<String>.from(parsed['flags'] ?? []),
        fullResult: parsed,
        signature: signature,
        publicKey: publicKey,
      );

      setState(() => _isProcessing = false);

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ResultScreen(
              result: {
                ...parsed,
                'location': location,
                'timestamp': DateTime.now().toIso8601String(),
              },
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e')),
        );
      }
    }
  }

  Future<String?> _getLocation() async {
    try {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;

      final position = await Geolocator.getCurrentPosition();
      return '${position.latitude},${position.longitude}';
    } catch (e) {
      debugPrint('Location error: $e');
      return null;
    }
  }

  Map<String, dynamic> _parseAnalysisOutput(String rawOutput) {
    try {
      // Strip markdown if present
      String text = rawOutput.trim();
      if (text.startsWith('```')) {
        text = text.split('```')[1];
        if (text.startsWith('json')) text = text.substring(4);
        text = text.trim();
      }
      if (text.endsWith('```')) text = text.substring(0, text.length - 3).trim();

      return jsonDecode(text);
    } catch (e) {
      debugPrint('Parse error: $e');
      return {'risk_score': 50, 'risk_level': 'MODERATE', 'confidence': 0.0};
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          CameraPreview(_cameraController!),
          // Scan frame overlay
          Center(
            child: Container(
              width: 280,
              height: 350,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          // Processing indicator
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(
                      _processingStep,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          // Bottom button
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _scanPack,
                icon: const Icon(Icons.camera),
                label: const Text('Scan Pack'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  backgroundColor: Colors.blue.shade600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }
}
