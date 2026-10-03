import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final source = img.decodeImage(
    File('assets/branding/lw_app_logo.png').readAsBytesSync(),
  );
  if (source == null) throw StateError('Could not decode LW logo');

  final canvas = img.Image(width: 1024, height: 1024, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 255));
  final logo = img.copyResize(
    source,
    width: 760,
    interpolation: img.Interpolation.cubic,
  );
  img.compositeImage(
    canvas,
    logo,
    dstX: (canvas.width - logo.width) ~/ 2,
    dstY: (canvas.height - logo.height) ~/ 2,
  );
  File('assets/branding/lw_launcher.png')
      .writeAsBytesSync(img.encodePng(canvas));
}
