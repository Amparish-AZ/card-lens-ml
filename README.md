# CardLens ML AI Pipeline 🚀

This repository houses a complete, end-to-end Machine Learning pipeline for training an intelligent Business Card OCR and Layout-Aware Named Entity Recognition (NER) model. 

It was built starting from scratch by downloading raw datasets from around the internet, filtering them through intense human QA, and pushing them through an automated training pipeline.

## 🧠 Dataset Architecture
We thoroughly audited over 1,000 public dataset images from Hugging Face, Kaggle, and Roboflow. Because over 80% of open-source datasets are polluted with synthetic template images or mislabeled receipts, we aggressively purged the bad data to create a 100% verified, pure dataset of real-world camera photos:

- **Proprietary Expo Cards:** 55 physical, raw photos taken manually at industry conventions.
- **Kaggle Ultra-HD Camera Dataset:** 54 pristine, massive high-resolution photos.
- **Roboflow Dataset:** 136 annotated community-sourced real photos.
- **Total:** 245 Perfectly Verified Training Anchors.

## ⚙️ The 4-Phase Pipeline

1. **Bootstrapping (Phase 1):** Raw photos are fed into `PaddleOCR` (PP-OCRv4) to extract text content, bounding box coordinates, and semantic layouts.
2. **Human Verification (Phase 2):** Raw extracted text is manually audited and tagged with correct semantic labels (`NAME`, `PHONE`, `COMPANY`, `TITLE`) inside the `source_manifest.jsonl`.
3. **Immutable Registration (Phase 3):** Verified cards are hashed and locked into versioned, immutable snapshots within `ml/data/registry` to prevent data leaking between Training, Validation, and Test splits.
4. **Cloud Training (Phase 4):** This repository relies on GitHub Actions to auto-detect new dataset versions, provision Cloud GPUs, and automatically train the Layout-Aware NER model.

## 🎯 Production Output
Once Cloud Training concludes, the resulting `.onnx` models are automatically embedded directly into our Flutter Android Application to provide 100% offline, on-device AI scanning!
