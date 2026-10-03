import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class OcrLine {
  const OcrLine({
    required this.text,
    required this.top,
    required this.left,
    required this.height,
  });
  final String text;
  final double top, left, height;

  static List<OcrLine> sortAdaptively(List<OcrLine> lines) {
    if (lines.length <= 1) return lines;
    final avgHeight = lines.map((e) => e.height).reduce((a, b) => a + b) / lines.length;
    final tolerance = (avgHeight * 0.45).clamp(4.0, 32.0);
    final sorted = List<OcrLine>.from(lines);
    sorted.sort((a, b) {
      if ((a.top - b.top).abs() < tolerance) return a.left.compareTo(b.left);
      return a.top.compareTo(b.top);
    });
    return sorted;
  }
}

class OcrResult {
  const OcrResult(this.text, this.previewPath, this.lines);
  final String text, previewPath;
  final List<OcrLine> lines;
}

class CardOcrService {
  Future<OcrResult> recognize(String sourcePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final candidates = <({String text, String path, List<OcrLine> lines})>[];
      final failures = <String>[];
      Future<bool> process(String path) async {
        RecognizedText result;
        try {
          result = await recognizer
              .processImage(InputImage.fromFilePath(path))
              .timeout(const Duration(seconds: 30));
        } catch (error, stackTrace) {
          failures.add(error.toString());
          debugPrint('CardLens OCR failed for $path: $error\n$stackTrace');
          return false;
        }
        if (result.text.trim().isNotEmpty) {
          final lines = _orderedLines(result);
          candidates.add((
            text: lines.map((e) => e.text).join('\n'),
            path: path,
            lines: lines,
          ));
          // Avoid a second expensive OCR pass when the normalized image already
          // contains strong business-card signals.
          return _hasStrongContactSignal(result.text);
        }
        return false;
      }

      final originalIsStrong = await process(sourcePath);
      if (!originalIsStrong) {
        final directory = await getTemporaryDirectory();
        final variants = await Isolate.run(
          () => _prepareImages(sourcePath, directory.path),
        );
        for (final path in variants) {
          if (await process(path)) break;
        }
      }
      if (candidates.isEmpty) {
        if (failures.isNotEmpty) {
          throw FormatException(
            'The OCR engine could not process this image. ${failures.first}',
          );
        }
        throw const FormatException(
          'No readable text found. Fill the frame with the card and avoid blur or glare.',
        );
      }
      candidates.sort((a, b) => _score(b.text).compareTo(_score(a.text)));
      final best = candidates.first;
      return OcrResult(best.text, best.path, best.lines);
    } finally {
      await recognizer.close();
    }
  }

  static List<OcrLine> _orderedLines(RecognizedText result) {
    final lines = <OcrLine>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        lines.add(
          OcrLine(
            text: line.text.trim(),
            top: line.boundingBox.top,
            left: line.boundingBox.left,
            height: line.boundingBox.height,
          ),
        );
      }
    }
    final sorted = OcrLine.sortAdaptively(lines);
    return sorted.where((e) => e.text.isNotEmpty).toList();
  }

  static int _score(String text) {
    final readable = RegExp(r'[A-Za-z0-9]').allMatches(text).length;
    final email = RegExp(r'\S+@\S+\.\S+').hasMatch(text) ? 100 : 0;
    final phone = RegExp(r'\+?\d[\d ()\-.]{6,}\d').hasMatch(text) ? 70 : 0;
    final lines = text.split('\n').where((e) => e.trim().length > 1).length;
    return readable + email + phone + (lines.clamp(0, 15) * 4);
  }

  static bool _hasStrongContactSignal(String text) =>
      RegExp(r'\S+@\S+\.\S+').hasMatch(text) &&
      RegExp(r'\+?\d[\d ()\-.]{6,}\d').hasMatch(text) &&
      RegExp(r'[A-Za-z0-9]').allMatches(text).length > 70;

  static List<String> _prepareImages(String sourcePath, String tempPath) {
    final decoded = img.decodeImage(File(sourcePath).readAsBytesSync());
    if (decoded == null) return [sourcePath];
    var source = img.bakeOrientation(decoded);
    final longest = source.width > source.height ? source.width : source.height;
    final shortest = source.width < source.height
        ? source.width
        : source.height;
    if (shortest < 900) {
      final scale = 900 / shortest;
      source = img.copyResize(
        source,
        width: (source.width * scale).round().clamp(1, 2400),
        height: (source.height * scale).round().clamp(1, 2400),
        interpolation: img.Interpolation.cubic,
      );
    } else if (longest > 2400) {
      final scale = 2400 / longest;
      source = img.copyResize(
        source,
        width: (source.width * scale).round(),
        height: (source.height * scale).round(),
        interpolation: img.Interpolation.cubic,
      );
    }
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final normalized = '$tempPath/cardlens_${stamp}_normalized.jpg';
    final enhanced = '$tempPath/cardlens_${stamp}_enhanced.jpg';
    var colorEnhanced = img.normalize(img.Image.from(source), min: 0, max: 255);
    colorEnhanced = img.contrast(colorEnhanced, contrast: 112);
    File(normalized)
        .writeAsBytesSync(img.encodeJpg(colorEnhanced, quality: 97));
    var highContrast = img.grayscale(img.Image.from(source));
    highContrast = img.contrast(highContrast, contrast: 135);
    File(enhanced).writeAsBytesSync(img.encodeJpg(highContrast, quality: 96));
    // Try untouched pixels first. ML Kit understands camera EXIF orientation and
    // often performs best before any Dart-side recompression.
    return [normalized, enhanced];
  }
}
