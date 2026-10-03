import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Normalized crop region relative to screen coordinates.
class CardCropRegion {
  final double left;
  final double top;
  final double width;
  final double height;
  final double screenWidth;
  final double screenHeight;

  const CardCropRegion({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.screenWidth,
    required this.screenHeight,
  });
}

class ImageEnhancer {
  /// Crops the image to the card guide region and enhances contrast for OCR.
  static Future<String> cropAndEnhance({
    required String inputPath,
    required String outputPath,
    required CardCropRegion region,
    double safetyPadding = 0.04,
  }) async {
    return compute(_cropAndEnhanceWorker, {
      'inputPath': inputPath,
      'outputPath': outputPath,
      'left': region.left,
      'top': region.top,
      'width': region.width,
      'height': region.height,
      'screenWidth': region.screenWidth,
      'screenHeight': region.screenHeight,
      'safetyPadding': safetyPadding,
    });
  }

  static String _cropAndEnhanceWorker(Map<String, dynamic> args) {
    final inputPath = args['inputPath'] as String;
    final outputPath = args['outputPath'] as String;
    final left = args['left'] as double;
    final top = args['top'] as double;
    final width = args['width'] as double;
    final height = args['height'] as double;
    final screenW = args['screenWidth'] as double;
    final screenH = args['screenHeight'] as double;
    final padding = args['safetyPadding'] as double;

    final bytes = File(inputPath).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      File(inputPath).copySync(outputPath);
      return outputPath;
    }

    final source = img.bakeOrientation(decoded);
    final imgW = source.width.toDouble();
    final imgH = source.height.toDouble();

    // Determine scale between camera sensor frame and screen layout
    final scaleX = imgW / screenW;
    final scaleY = imgH / screenH;
    final scale = math.max(scaleX, scaleY);
    final renderedW = screenW * scale;
    final renderedH = screenH * scale;
    final offsetX = (renderedW - imgW) / 2.0;
    final offsetY = (renderedH - imgH) / 2.0;

    // Apply safety margin (e.g. 4%) around card guide
    final padX = width * padding;
    final padY = height * padding;

    final cropScreenLeft = math.max(0.0, left - padX);
    final cropScreenTop = math.max(0.0, top - padY);
    final cropScreenWidth = width + padX * 2.0;
    final cropScreenHeight = height + padY * 2.0;

    var cropX = ((cropScreenLeft * scale) - offsetX).round();
    var cropY = ((cropScreenTop * scale) - offsetY).round();
    var cropW = (cropScreenWidth * scale).round();
    var cropH = (cropScreenHeight * scale).round();

    // Boundary clamps
    cropX = cropX.clamp(0, source.width - 1);
    cropY = cropY.clamp(0, source.height - 1);
    if (cropX + cropW > source.width) cropW = source.width - cropX;
    if (cropY + cropH > source.height) cropH = source.height - cropY;

    img.Image processed;
    if (cropW > 100 && cropH > 60) {
      processed = img.copyCrop(
        source,
        x: cropX,
        y: cropY,
        width: cropW,
        height: cropH,
      );
    } else {
      processed = source;
    }

    // Enhance image: boost contrast slightly to make text stand out against backgrounds / glare
    final enhanced = img.contrast(processed, contrast: 118);

    File(outputPath).writeAsBytesSync(img.encodeJpg(enhanced, quality: 95));
    return outputPath;
  }
}
