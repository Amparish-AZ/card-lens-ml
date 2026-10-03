# CardLens

A privacy-first Flutter business-card scanner for Android and iOS.

## Pipeline

1. `image_picker` captures a camera image or selects one from the gallery.
2. Android uses PP-OCRv6 Small through ONNX Runtime. NNAPI dispatches supported
   operations to mobile GPU/NPU/DSP hardware, with CPU fallback.
3. Google ML Kit remains the automatic Android fallback and the iOS OCR engine.
4. `card_field_classifier.tflite` classifies OCR lines as name, title, company,
   email, phone, website, or address.
5. Regex validation protects syntax-critical email, phone, and website fields.
6. The user reviews and edits every extracted field before confirming.

No card image or contact text is sent to a server.

## Training and model releases

The app and ML lifecycle are separated. A private training runner or Google Colab
validates versioned datasets, trains/fine-tunes models, evaluates independent test
cards, and publishes immutable model artifacts. A new app release bundles an
approved model release; production inference remains offline.

See [the ML workspace](ml/README.md) and
[the model lifecycle](docs/MODEL_LIFECYCLE.md) for dataset contracts, checksums,
quality gates, GitHub workflows, and rollback rules.

## Run

```sh
flutter pub get
flutter run
```

## Verify and build

```sh
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

The tiny classifier can be regenerated with
`python tool/build_field_classifier.py` after installing Python packages
`flatbuffers`, `numpy`, and `tflite`.

The preserved ML Kit-only release is under `releases/cardlens-1.6.0-mlkit/`.
PaddleOCR's Android SDK source and Apache 2.0 license are under
`android/ppocr-sdk/`.

> OCR accuracy depends on lighting, focus, font, language, and card layout.
> CardLens therefore requires a human review step rather than claiming that
> any OCR/NER combination can guarantee zero errors.
