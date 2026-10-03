import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

String _rectifyImage(
  String inputPath,
  String outputPath,
  List<double> coordinates,
) {
  final decoded = img.decodeImage(File(inputPath).readAsBytesSync());
  if (decoded == null) throw const FormatException('Invalid image');
  final source = img.bakeOrientation(decoded);
  final normalized = <math.Point<double>>[
    for (var i = 0; i < coordinates.length; i += 2)
      math.Point(coordinates[i], coordinates[i + 1]),
  ];
  img.Point point(math.Point<double> value) =>
      img.Point(value.x * (source.width - 1), value.y * (source.height - 1));
  double distance(math.Point<double> a, math.Point<double> b) => math.sqrt(
    math.pow((a.x - b.x) * source.width, 2) +
        math.pow((a.y - b.y) * source.height, 2),
  );
  final width = math
      .max(
        distance(normalized[0], normalized[1]),
        distance(normalized[2], normalized[3]),
      )
      .round()
      .clamp(500, 1600);
  final height = math
      .max(
        distance(normalized[0], normalized[2]),
        distance(normalized[1], normalized[3]),
      )
      .round()
      .clamp(300, 1600);
  final corrected = img.copyRectify(
    source,
    topLeft: point(normalized[0]),
    topRight: point(normalized[1]),
    bottomLeft: point(normalized[2]),
    bottomRight: point(normalized[3]),
    interpolation: img.Interpolation.linear,
    toImage: img.Image(width: width, height: height),
  );
  File(outputPath).writeAsBytesSync(img.encodeJpg(corrected, quality: 97));
  return outputPath;
}

String _rectifyWorker(Map<String, Object> request) => _rectifyImage(
  request['inputPath']! as String,
  request['outputPath']! as String,
  (request['coordinates']! as List).cast<double>(),
);

class PerspectiveCorrectionPage extends StatefulWidget {
  const PerspectiveCorrectionPage({super.key, required this.imagePath});
  final String imagePath;

  @override
  State<PerspectiveCorrectionPage> createState() =>
      _PerspectiveCorrectionPageState();
}

class _PerspectiveCorrectionPageState extends State<PerspectiveCorrectionPage> {
  final points = <Offset>[
    const Offset(.025, .025),
    const Offset(.975, .025),
    const Offset(.025, .975),
    const Offset(.975, .975),
  ];
  Size? sourceSize;
  bool working = false;

  @override
  void initState() {
    super.initState();
    _readSize();
  }

  Future<void> _readSize() async {
    final imagePath = widget.imagePath;
    try {
      final completer = Completer<Size>();
      final stream = FileImage(File(imagePath))
          .resolve(const ImageConfiguration());
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) {
            completer.complete(
              Size(info.image.width.toDouble(), info.image.height.toDouble()),
            );
          }
          stream.removeListener(listener);
        },
        onError: (Object error, StackTrace? stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);
      final size = await completer.future.timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() => sourceSize = size);
    } catch (_) {
      // Never trap the user on this optional page if an unusual image cannot
      // be decoded. Continue with the cropped original instead.
      if (mounted) Navigator.pop(context, imagePath);
    }
  }

  Future<void> _finish({required bool rectify}) async {
    if (!rectify) {
      Navigator.pop(context, widget.imagePath);
      return;
    }
    setState(() => working = true);
    try {
      final directory = await getTemporaryDirectory();
      final outputPath =
          '${directory.path}${Platform.pathSeparator}cardlens_rectified_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final coordinates = <double>[
        for (final point in points) ...[point.dx, point.dy],
      ];
      final inputPath = widget.imagePath;
      final result = await compute(_rectifyWorker, <String, Object>{
        'inputPath': inputPath,
        'outputPath': outputPath,
        'coordinates': coordinates,
      }).timeout(const Duration(seconds: 18), onTimeout: () => inputPath);
      if (mounted) Navigator.pop(context, result);
    } catch (error, stackTrace) {
      debugPrint('Perspective correction failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not straighten this image')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF111114),
    appBar: AppBar(
      backgroundColor: const Color(0xFF111114),
      foregroundColor: Colors.white,
      title: const Text(
        'Straighten card',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      actions: [
        TextButton(
          onPressed: working ? null : () => _finish(rectify: false),
          child: const Text('Skip', style: TextStyle(color: Colors.white70)),
        ),
      ],
    ),
    body: sourceSize == null
        ? const Center(child: CircularProgressIndicator(color: Colors.white))
        : Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 10),
                child: Text(
                  'Move each blue handle onto a card corner.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final fitted = applyBoxFit(
                      BoxFit.contain,
                      sourceSize!,
                      constraints.biggest,
                    );
                    final rect = Alignment.center.inscribe(
                      fitted.destination,
                      Offset.zero & constraints.biggest,
                    );
                    return Stack(
                      children: [
                        Positioned.fromRect(
                          rect: rect,
                          child: Image.file(
                            File(widget.imagePath),
                            fit: BoxFit.fill,
                            cacheWidth: 1600,
                          ),
                        ),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _PerspectivePainter(rect, points),
                          ),
                        ),
                        for (var index = 0; index < points.length; index++)
                          _handle(index, rect),
                      ],
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: working ? null : () => _finish(rectify: true),
                      icon: working
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.crop_free),
                      label: const Text('Straighten and continue'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFB8D4EE),
                        foregroundColor: const Color(0xFF203247),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
  );

  Widget _handle(int index, Rect rect) {
    const diameter = 38.0;
    final position = Offset(
      rect.left + points[index].dx * rect.width,
      rect.top + points[index].dy * rect.height,
    );
    return Positioned(
      left: position.dx - diameter / 2,
      top: position.dy - diameter / 2,
      width: diameter,
      height: diameter,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => setState(() {
          points[index] = Offset(
            (points[index].dx + details.delta.dx / rect.width).clamp(0, 1),
            (points[index].dy + details.delta.dy / rect.height).clamp(0, 1),
          );
        }),
        child: const Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFF76B7F2),
              shape: BoxShape.circle,
              border: Border.fromBorderSide(
                BorderSide(color: Colors.white, width: 2),
              ),
            ),
            child: SizedBox(width: 22, height: 22),
          ),
        ),
      ),
    );
  }
}

class _PerspectivePainter extends CustomPainter {
  const _PerspectivePainter(this.imageRect, this.points);
  final Rect imageRect;
  final List<Offset> points;

  Offset position(int index) => Offset(
    imageRect.left + points[index].dx * imageRect.width,
    imageRect.top + points[index].dy * imageRect.height,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(position(0).dx, position(0).dy)
      ..lineTo(position(1).dx, position(1).dy)
      ..lineTo(position(3).dx, position(3).dy)
      ..lineTo(position(2).dx, position(2).dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF76B7F2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_PerspectivePainter oldDelegate) => true;
}
