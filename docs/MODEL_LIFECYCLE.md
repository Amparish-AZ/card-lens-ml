# CardLens model lifecycle

## Architecture decision

CardLens performs inference offline. A training machine or Google Colab is used
only to validate data, train models, evaluate them, and publish versioned model
artifacts. Released devices never upload a card image or extracted contact data.

```text
Private Git LFS dataset registry (all verified batches)
          |
          v
Training runner / Colab ----> metrics and evaluation report
          |                              |
          v                              v
 OCR ONNX + layout NER TFLite ---> quality gates
                                          |
                                          v
                              immutable model release
                                          |
                                          v
                                new Flutter app build
                                          |
                                          v
                                offline device inference
```

## Repository areas

| Area | Responsibility |
| --- | --- |
| `ml/data/registry` | Immutable, versioned, aggregate real-card training batches |
| `ml/schemas` | Machine-readable dataset and release schemas |
| `ml/src/cardlens_ml` | Dataset validation, quality gates, checksums, packaging |
| `ml/scripts` | Desktop OCR, compact NER training, and OCR fine-tuning entrypoints |
| `tool` | Existing compact field-parser trainer and labelled lines |
| `android/ppocr-sdk/.../models` | Android detector and recognizer consumed by the app |
| `assets/models` | Cross-platform TFLite parser and bundled model manifest |
| `.github/workflows` | Quality checks, model packaging, and mobile builds |

## Dataset versions

1. Assign every physical card a stable `card_id`.
2. Remove byte-identical and visually duplicated cards.
3. Store raw OCR text and human-corrected text separately.
4. Store normalized line coordinates and the semantic label.
5. Split by complete card, never by individual line crop.
6. Keep test cards unchanged and excluded from synthetic augmentation.
7. Increment the dataset version whenever records, labels, or split membership change.

Raw card images and annotations contain personal information. They belong in a
private repository or restricted object storage, never a public GitHub repository.

## Training stages

### Layout-aware NER parser

`ml/scripts/train_layout_ner.py` consumes all verified registry batches. It learns
from each OCR line's UTF-8 characters, normalized geometry, OCR confidence, reading
order, relative text size, and general lexical shape. Synthetic cards are generated
for the training split only; validation and test remain real and frozen. The TFLite
model accepts at most 32 lines with 96 UTF-8 bytes per line and is designed for
offline mobile inference.

### OCR recognizer

`ml/scripts/run_ocr_training.py` fine-tunes the official PP-OCRv6 Small checkpoint
from an external PaddleOCR checkout. It expects line crops and tab-separated
transcriptions in `recognition/train.txt` and `recognition/validation.txt`.

The Paddle inference export must then be converted to ONNX and benchmarked against
the existing Android decoder. Conversion is deliberately a separate controlled
stage so a shape, character dictionary, or decoder change cannot silently enter
the mobile application.

## Evaluation and approval

Training-set accuracy is never a release criterion. `ml/config/layout_ner_gates.json`
defines the independent-test release gates for the new parser. The older
`ml/config/pipeline.json` remains available for the end-to-end OCR benchmark:

- OCR character error rate
- Exact email and phone recognition
- Name and company F1
- Android 95th-percentile processing time

Every candidate is compared with the currently released model on the same frozen
test cards. A candidate is rejected if any required metric is missing or fails its
gate. Human review remains mandatory because no OCR system guarantees perfect text.

## Model release contents

An approved release contains detector ONNX, recognizer ONNX, recognizer character
configuration, the legacy parser during migration, layout NER TFLite, metrics, and
`manifest.json`. The manifest records:

- Model and dataset versions
- Source revision
- Creation time
- Artifact sizes
- SHA-256 checksums

Model releases are immutable. A correction produces a new version instead of
overwriting an old release, which preserves rollback capability.

## App release

The mobile build workflow downloads an approved model release, verifies every
checksum, installs the artifacts in the known Flutter/Android locations, executes
tests, and builds a new APK/AAB and unsigned iOS build. Store signing is a separate
protected release step.

Android currently uses the PP-OCRv6 ONNX model. iOS currently uses ML Kit OCR and
the shared TFLite parser; using the same fine-tuned recognizer on iOS will require
an ONNX Runtime or Core ML integration in a later app release.
