# CardLens ML workspace

This directory is the training and model-versioning side of CardLens. Production
card images are never sent here by the released Flutter app. Training is run only
when a versioned dataset changes, and approved models are bundled into a new app.

## Responsibilities

- Validate card-level train, validation, and test splits.
- Preserve both raw OCR output and corrected transcription.
- Train/fine-tune models outside the Flutter runtime.
- Reject incomplete datasets, duplicate cards, and regressed metrics.
- Package immutable model releases with SHA-256 checksums.
- Install only verified releases into the Flutter asset locations.

## Dataset contract

The active dataset follows `schemas/card-dataset.schema.json`:

```text
dataset-v1.0/
├── annotations/cards.jsonl
├── images/
└── recognition/
    ├── crops/
    ├── train.txt
    └── validation.txt
```

Each complete physical card belongs to exactly one split. Crops from a card must
never be distributed across train and validation/test splits.

The layout-aware NER dataset uses `schemas/card-ner-dataset.schema.json` and
word-level BIO tags. Repeated photographs of one physical card share the same
`physical_card_group`, which the validator prevents from leaking across splits.

Validate a human-reviewed NER dataset before training:

```sh
python -m cardlens_ml validate-ner-dataset \
  --dataset path/to/ner-dataset \
  --require-images \
  --require-verified
```

Raw image archives are first inventoried into a non-training review queue. The
`--same-card` option keeps repeated photographs of one physical card together:

```sh
python -m cardlens_ml prepare-ner-source \
  --source-dir path/to/extracted/images \
  --output path/to/source-manifest.jsonl \
  --source-name kaggle-business-cards \
  --source-license unknown \
  --same-card "view-a.jpg,view-b.jpg"
```

Only NER entity tags reviewed against the source card and marked
`verified: true` are accepted by the NER training command. Corrected character
transcriptions for OCR fine-tuning are maintained separately under
`recognition/`; NER training intentionally consumes the OCR engine's observed
text. A source manifest alone is never training data.

## Desktop OCR annotation bootstrap

The desktop command uses the same PP-OCRv6 ONNX detector and recognizer bundled
with the Android application. These dependencies are development-only and do
not increase the APK size.

For the staged Kaggle cards, run the complete OCR, draft-label and validation
workflow from PowerShell:

```powershell
.\tool\prepare_kaggle_ner.ps1
```

After changing only semantic overrides, reuse the existing OCR output:

```powershell
.\tool\prepare_kaggle_ner.ps1 -SkipOcr
```

Validate a dataset:

```sh
python -m pip install -e "ml[dev]"
python -m cardlens_ml validate-dataset --dataset path/to/dataset --require-images
```

## Accumulating batches and training on GitHub

Each human-verified batch is registered once under `ml/data/registry`. Registration
copies the images and annotations into an immutable versioned directory, rejects
duplicate images/card IDs, and prevents photographs of the same physical card from
leaking across train, validation, and test splits:

On Windows, use the guarded helper:

```powershell
.\tool\register_ner_batch.ps1 `
  -Source .\ml\data\private\my-reviewed-batch `
  -DatasetId office-cards `
  -DatasetVersion 1.0.0 `
  -Python C:\Users\you\cardlens-ml\Scripts\python.exe
```

Or call the portable CLI directly:

```sh
python -m cardlens_ml register-ner-dataset \
  --source ml/data/private/my-reviewed-batch \
  --registry ml/data/registry \
  --dataset-id office-cards \
  --dataset-version 1.0.0
```

Commit and push that new registry directory. In GitHub, open **Actions > Train and
package CardLens NER > Run workflow** and enter a new model version. The workflow:

1. downloads every Git LFS image;
2. validates and combines every registered batch;
3. adds synthetic English cards only to the training split;
4. trains and evaluates the compact layout-aware TFLite NER;
5. always uploads the candidate model and complete metrics for inspection;
6. blocks packaging/release unless the frozen test set passes the gates in
   `ml/config/layout_ner_gates.json`; and
7. optionally publishes a checksum-protected immutable GitHub Release.

Training jobs are serialized, so two runs cannot overwrite or compete with one
another. The Flutter app never uploads users' scanned cards automatically.

## Model release

After training and independent evaluation, package the approved artifacts:

```sh
python -m cardlens_ml package-release \
  --model-version 1.1.0 \
  --dataset-version 1.0.0 \
  --artifact ocr_detector=android/ppocr-sdk/src/main/assets/models/det/inference.onnx \
  --artifact ocr_recognizer=android/ppocr-sdk/src/main/assets/models/rec/inference.onnx \
  --artifact ocr_recognizer_config=android/ppocr-sdk/src/main/assets/models/rec/inference.yml \
  --artifact field_parser=assets/models/card_field_classifier.tflite \
  --artifact parser_metrics=assets/models/training_metrics.json \
  --artifact layout_ner=ml/dist/trained/layout_ner.tflite \
  --artifact layout_ner_metadata=ml/dist/trained/layout_ner_metadata.json \
  --artifact layout_ner_metrics=ml/dist/trained/layout_ner_metrics.json \
  --output ml/dist
```

Install a downloaded release only after checksum verification:

```sh
python -m cardlens_ml install-release \
  --release ml/dist/cardlens-models-1.1.0 \
  --project .
```

See `docs/MODEL_LIFECYCLE.md` for the full workflow and release responsibilities.
