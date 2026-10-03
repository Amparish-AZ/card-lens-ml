import 'ocr_service.dart';

/// On-device OCR powered by Google ML Kit text recognition.
/// High accuracy, low latency, and lightweight without heavy native binaries.
class MobileOcrService {
  Future<OcrResult> recognize(String sourcePath) async {
    return CardOcrService().recognize(sourcePath);
  }
}
