import 'dart:convert';
import 'dart:io';

import 'package:card_lens/field_classifier.dart';
import 'package:card_lens/mobile_ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('extract all supplied business cards', (tester) async {
    const directory =
        '/sdcard/Android/data/com.cardlens.card_lens/files/test_cards';
    final cardDirectory = Directory(directory);
    for (
      var attempt = 0;
      attempt < 90 &&
          (!cardDirectory.existsSync() ||
              cardDirectory.listSync().whereType<File>().length != 19);
      attempt++
    ) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final images = cardDirectory.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(images, hasLength(19));
    for (final image in images) {
      try {
        final ocr = await MobileOcrService().recognize(image.path);
        final parsed = await SmartBusinessCardParser.parse(
          ocr.text,
          layout: ocr.lines,
        );
        // A stable prefix makes the device output machine-readable.
        // ignore: avoid_print
        print(
          'CARDLENS_RESULT ${jsonEncode({'image': image.uri.pathSegments.last, 'raw_lines': ocr.text.split('\n'), ...parsed.toSchemaInstance()})}',
        );
      } catch (error) {
        // ignore: avoid_print
        print(
          'CARDLENS_RESULT ${jsonEncode({'image': image.uri.pathSegments.last, 'error': error.toString()})}',
        );
      }
    }
  });
}
