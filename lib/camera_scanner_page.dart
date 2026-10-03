import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'image_enhancer.dart';

class CameraScannerPage extends StatefulWidget {
  const CameraScannerPage({super.key});
  @override
  State<CameraScannerPage> createState() => _CameraScannerPageState();
}

class _CameraScannerPageState extends State<CameraScannerPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _busy = false;
  bool _flash = false;
  bool _autoCapture = true;
  bool _isVertical = false;
  double _lockProgress = 0.0;
  bool _cardLocked = false;
  Timer? _lockTimer;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
      if (!mounted) return;
      setState(() => _controller = controller);
      _startAutoCaptureDetector();
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = e.description ?? e.code);
    }
  }

  int _warmupTicks = 14; // ~1.4s initial buffer so user can position phone without rush

  void _startAutoCaptureDetector() {
    _lockTimer?.cancel();
    _warmupTicks = 14;
    _lockProgress = 0.0;
    _cardLocked = false;
    _lockTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _busy || !_autoCapture) return;
      final controller = _controller;
      if (controller == null || !controller.value.isInitialized) return;

      if (_warmupTicks > 0) {
        setState(() => _warmupTicks--);
        return;
      }

      if (_lockProgress < 1.0) {
        setState(() {
          _lockProgress = (_lockProgress + 0.04).clamp(0.0, 1.0);
          if (_lockProgress >= 1.0 && !_cardLocked) {
            _cardLocked = true;
            HapticFeedback.mediumImpact();
            _capture();
          }
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _lockTimer?.cancel();
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _start();
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    _lockTimer?.cancel();
    setState(() => _busy = true);

    try {
      await controller.setFocusMode(FocusMode.locked);
      await Future<void>.delayed(const Duration(milliseconds: 180));
      final rawImage = await controller.takePicture();

      if (!mounted) return;
      final size = MediaQuery.of(context).size;
      final double guideWidth;
      final double guideHeight;
      if (_isVertical) {
        guideHeight = math.min(size.height * 0.58, (size.width - 48) * 1.586);
        guideWidth = guideHeight / 1.586;
      } else {
        guideWidth = size.width - 38;
        guideHeight = guideWidth / 1.586;
      }
      final guideRect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height * .43),
        width: guideWidth,
        height: guideHeight,
      );

      final region = CardCropRegion(
        left: guideRect.left,
        top: guideRect.top,
        width: guideRect.width,
        height: guideRect.height,
        screenWidth: size.width,
        screenHeight: size.height,
      );

      final tempDir = await getTemporaryDirectory();
      final enhancedPath =
          '${tempDir.path}/card_enhanced_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await ImageEnhancer.cropAndEnhance(
        inputPath: rawImage.path,
        outputPath: enhancedPath,
        region: region,
      );

      if (mounted) {
        Navigator.pop(context, XFile(enhancedPath));
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _cardLocked = false;
          _lockProgress = 0.0;
        });
        _startAutoCaptureDetector();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    _flash = !_flash;
    await controller.setFlashMode(_flash ? FlashMode.torch : FlashMode.off);
    if (mounted) setState(() {});
  }

  void _toggleAutoCapture() {
    setState(() {
      _autoCapture = !_autoCapture;
      _lockProgress = 0.0;
      _cardLocked = false;
    });
    if (_autoCapture) {
      _startAutoCaptureDetector();
    } else {
      _lockTimer?.cancel();
    }
  }

  void _toggleOrientation() {
    HapticFeedback.selectionClick();
    setState(() {
      _isVertical = !_isVertical;
      _warmupTicks = 12;
      _lockProgress = 0.0;
      _cardLocked = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lockTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (controller != null && controller.value.isInitialized)
              Center(child: CameraPreview(controller))
            else
              Center(
                child: _error == null
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Padding(
                        padding: const EdgeInsets.all(30),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
              ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_busy) return;
                setState(() {
                  _warmupTicks = 12;
                  _lockProgress = 0.0;
                  _cardLocked = false;
                });
              },
              child: CustomPaint(
                painter: _CardGuidePainter(
                  progress: _lockProgress,
                  isLocked: _cardLocked,
                  isVertical: _isVertical,
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              top: 14,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _roundButton(Icons.close, () => Navigator.pop(context)),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: _toggleOrientation,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _isVertical
                                ? const Color(0xFF7390FF).withValues(alpha: 0.85)
                                : Colors.black45,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _isVertical
                                  ? const Color(0xFF7390FF)
                                  : Colors.white38,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isVertical
                                    ? Icons.crop_portrait
                                    : Icons.crop_landscape,
                                color: Colors.white,
                                size: 15,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _isVertical ? 'PORTRAIT' : 'LANDSCAPE',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _toggleAutoCapture,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _autoCapture
                                ? const Color(0xFF34C759).withValues(alpha: 0.85)
                                : Colors.black45,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _autoCapture
                                  ? const Color(0xFF34C759)
                                  : Colors.white38,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _autoCapture
                                    ? Icons.auto_awesome
                                    : Icons.touch_app,
                                color: Colors.white,
                                size: 15,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _autoCapture ? 'AUTO' : 'MANUAL',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _roundButton(
                        _flash ? Icons.flash_on : Icons.flash_off,
                        _toggleFlash,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              left: 30,
              right: 30,
              bottom: 124,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _cardLocked
                            ? const Color(0xFF34C759)
                            : Colors.white24,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      _busy
                          ? 'Cropping & enhancing card image...'
                          : _cardLocked
                              ? 'Card locked! Capturing...'
                              : _autoCapture
                                  ? (_warmupTicks > 0
                                      ? 'Position card inside frame...'
                                      : 'Hold steady — Capturing in ${((1.0 - _lockProgress) * 2.5).ceil().clamp(1, 3)}s')
                                  : 'Align card inside frame & tap shutter',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _cardLocked
                            ? const Color(0xFF34C759)
                            : Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _autoCapture
                        ? (_isVertical
                            ? 'Vertical card mode active • Tap to pause'
                            : 'Tap anywhere to pause / reset')
                        : 'Auto-crops edges & removes glare',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _busy ? null : _capture,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 82,
                        height: 82,
                        child: CircularProgressIndicator(
                          value: _autoCapture ? _lockProgress : 0.0,
                          strokeWidth: 4,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _cardLocked
                                ? const Color(0xFF34C759)
                                : const Color(0xFF7390FF),
                          ),
                          backgroundColor: Colors.white24,
                        ),
                      ),
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _cardLocked
                              ? const Color(0xFF34C759)
                              : Colors.white,
                        ),
                        child: _busy
                            ? const Padding(
                                padding: EdgeInsets.all(18),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.black87,
                                ),
                              )
                            : Icon(
                                _autoCapture
                                    ? Icons.camera_alt
                                    : Icons.camera,
                                color: Colors.black87,
                                size: 28,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundButton(IconData icon, VoidCallback action) => Material(
        color: Colors.black45,
        shape: const CircleBorder(),
        child: IconButton(
          onPressed: action,
          icon: Icon(icon, color: Colors.white),
        ),
      );
}

class _CardGuidePainter extends CustomPainter {
  final double progress;
  final bool isLocked;
  final bool isVertical;

  _CardGuidePainter({
    required this.progress,
    required this.isLocked,
    this.isVertical = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double width;
    final double height;
    if (isVertical) {
      height = math.min(size.height * 0.58, (size.width - 48) * 1.586);
      width = height / 1.586;
    } else {
      width = size.width - 38;
      height = width / 1.586;
    }
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * .43),
      width: width,
      height: height,
    );
    final shade = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(18)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      shade,
      Paint()..color = Colors.black.withValues(alpha: .52),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(18)),
      Paint()
        ..color = isLocked
            ? const Color(0xFF34C759)
            : Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isLocked ? 2.5 : 1.8,
    );

    final cornerColor = isLocked
        ? const Color(0xFF34C759)
        : Color.lerp(
            const Color(0xFF7390FF),
            const Color(0xFF34C759),
            progress,
          )!;

    final corner = Paint()
      ..color = cornerColor
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round;
    const length = 30.0;
    for (final point in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      final sx = point.dx == rect.left ? 1.0 : -1.0;
      final sy = point.dy == rect.top ? 1.0 : -1.0;
      canvas.drawLine(point, point + Offset(sx * length, 0), corner);
      canvas.drawLine(point, point + Offset(0, sy * length), corner);
    }
  }

  @override
  bool shouldRepaint(covariant _CardGuidePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.isLocked != isLocked ||
      oldDelegate.isVertical != isVertical;
}
