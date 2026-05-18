import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CaptureScreen
//
// Full-screen camera UI pushed by ScannerScreen when the user taps
// "Analyze Medicine".  Returns an [XFile] when confirmed, or [null] if the
// user discards without taking a photo.
//
// Two internal states:
//   • Viewfinder — live preview + shutter button + flash toggle + close
//   • Review     — captured image + "Retake" / "Use Photo"
// ─────────────────────────────────────────────────────────────────────────────
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _initializing = true;
  String? _initError;

  XFile? _captured;     // non-null → review mode
  bool _capturing = false;
  FlashMode _flashMode = FlashMode.auto;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Enter immersive mode so the camera fills the full display.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _controller?.dispose();
    super.dispose();
  }

  /// Pause / resume camera when the app goes to background / foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  // ── Camera init ────────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    setState(() {
      _initializing = true;
      _initError = null;
    });
    try {
      final List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('No cameras found on this device');

      final CameraDescription camera = cameras.firstWhere(
        (CameraDescription c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final CameraController ctrl = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      await ctrl.setFlashMode(_flashMode);
      setState(() {
        _controller = ctrl;
        _initializing = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = e.toString();
          _initializing = false;
        });
      }
    }
  }

  // ── Camera controls ────────────────────────────────────────────────────────

  Future<void> _cycleFlash() async {
    final CameraController? ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final FlashMode next = _flashMode == FlashMode.off
        ? FlashMode.auto
        : _flashMode == FlashMode.auto
            ? FlashMode.always
            : FlashMode.off;
    await ctrl.setFlashMode(next);
    setState(() => _flashMode = next);
  }

  Future<void> _capture() async {
    final CameraController? ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final XFile file = await ctrl.takePicture();
      if (mounted) setState(() { _captured = file; _capturing = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _capturing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    }
  }

  void _retake() => setState(() => _captured = null);
  void _confirm() => Navigator.of(context).pop(_captured);
  void _discard() => Navigator.of(context).pop<XFile>(null);

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back gesture = discard
      canPop: true,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) Navigator.of(context).pop<XFile>(null);
      },
      child: _captured != null ? _buildReview() : _buildViewfinder(),
    );
  }

  // ── Viewfinder ─────────────────────────────────────────────────────────────

  Widget _buildViewfinder() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[

          // ── Camera preview ──────────────────────────────────────────────────
          if (_controller != null && _controller!.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: CameraPreview(_controller!),
              ),
            )
          else if (_initializing)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('Opening camera…',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
            )
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.camera_alt_outlined,
                        color: Colors.white54, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      _initError ?? 'Camera unavailable',
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: _initCamera,
                      child: const Text('Retry',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),

          // ── Corner guide overlay ────────────────────────────────────────────
          if (_controller != null && !_initializing)
            const _CornerGuideOverlay(),

          // ── Top bar: close | hint | flash ───────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  _CircleButton(icon: Icons.close, onTap: _discard),
                  const Text(
                    'Scan medicine pack',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      shadows: <Shadow>[
                        Shadow(blurRadius: 6, color: Colors.black54),
                      ],
                    ),
                  ),
                  _CircleButton(
                    icon: switch (_flashMode) {
                      FlashMode.off    => Icons.flash_off,
                      FlashMode.always => Icons.flash_on,
                      _                => Icons.flash_auto,
                    },
                    onTap: _cycleFlash,
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom: tip + shutter ───────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // Tip text
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Hold steady — place foil side flat and centred',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Shutter button
                    GestureDetector(
                      onTap: (_controller != null && !_capturing && !_initializing)
                          ? _capture
                          : null,
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          color: _capturing
                              ? Colors.white38
                              : Colors.transparent,
                        ),
                        child: _capturing
                            ? const Center(
                                child: SizedBox(
                                  width: 30,
                                  height: 30,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                ),
                              )
                            : Center(
                                child: Container(
                                  width: 60,
                                  height: 60,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Review ─────────────────────────────────────────────────────────────────

  Widget _buildReview() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[

          // Full-screen captured image
          Image.file(
            File(_captured!.path),
            fit: BoxFit.contain,
          ),

          // Top label
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Use this photo?',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom action bar
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: <Color>[Colors.black87, Colors.transparent],
                    stops: <double>[0.0, 1.0],
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    // Retake
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _retake,
                        icon: const Icon(Icons.refresh,
                            color: Colors.white, size: 18),
                        label: const Text(
                          'Retake',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white60),
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Use Photo
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _confirm,
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('Use Photo'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A6BCC),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                          textStyle: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black45,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

/// Draws a rounded-corner guide bracket in the centre of the screen to help
/// users frame the blister pack correctly.
class _CornerGuideOverlay extends StatelessWidget {
  const _CornerGuideOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _CornerGuidePainter());
  }
}

class _CornerGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const double cornerLen = 28.0;
    const double strokeW   = 3.0;
    const double radius    = 8.0;

    final Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Guide box: 82% wide, 52% tall, centred vertically a bit above middle
    final double gw = size.width  * 0.82;
    final double gh = size.height * 0.52;
    final double gl = (size.width  - gw) / 2;
    final double gt = (size.height - gh) / 2 - size.height * 0.04;
    final double gr = gl + gw;
    final double gb = gt + gh;

    // Top-left corner
    canvas
      ..drawLine(Offset(gl + radius, gt), Offset(gl + cornerLen, gt), paint)
      ..drawLine(Offset(gl, gt + radius), Offset(gl, gt + cornerLen), paint)
      ..drawArc(Rect.fromLTWH(gl, gt, radius * 2, radius * 2),
          -3.14 / 2 * 2, -3.14 / 2, false, paint);

    // Top-right corner
    canvas
      ..drawLine(Offset(gr - cornerLen, gt), Offset(gr - radius, gt), paint)
      ..drawLine(Offset(gr, gt + radius), Offset(gr, gt + cornerLen), paint)
      ..drawArc(Rect.fromLTWH(gr - radius * 2, gt, radius * 2, radius * 2),
          -3.14 / 2, -3.14 / 2, false, paint);

    // Bottom-left corner
    canvas
      ..drawLine(Offset(gl, gb - cornerLen), Offset(gl, gb - radius), paint)
      ..drawLine(Offset(gl + radius, gb), Offset(gl + cornerLen, gb), paint)
      ..drawArc(Rect.fromLTWH(gl, gb - radius * 2, radius * 2, radius * 2),
          3.14 / 2, 3.14 / 2, false, paint);

    // Bottom-right corner
    canvas
      ..drawLine(Offset(gr, gb - cornerLen), Offset(gr, gb - radius), paint)
      ..drawLine(Offset(gr - cornerLen, gb), Offset(gr - radius, gb), paint)
      ..drawArc(
          Rect.fromLTWH(gr - radius * 2, gb - radius * 2, radius * 2, radius * 2),
          0, 3.14 / 2, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
