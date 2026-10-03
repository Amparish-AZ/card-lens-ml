from __future__ import annotations

import argparse
import json
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from cardlens_ml.ner_contracts import NerCardAnnotation
from cardlens_ml.registry import discover_registry

MAX_LINES = 32
MAX_BYTES = 96
LAYOUT_FEATURES = 16
TAGS = (
    "O",
    "B-NAME",
    "I-NAME",
    "B-TITLE",
    "I-TITLE",
    "B-COMPANY",
    "I-COMPANY",
    "B-EMAIL",
    "I-EMAIL",
    "B-PHONE",
    "I-PHONE",
    "B-WEBSITE",
    "I-WEBSITE",
    "B-ADDRESS",
    "I-ADDRESS",
)
TAG_INDEX = {tag: index for index, tag in enumerate(TAGS)}


@dataclass(frozen=True)
class EncodedCard:
    characters: np.ndarray[Any, np.dtype[np.int32]]
    layout: np.ndarray[Any, np.dtype[np.float32]]
    labels: np.ndarray[Any, np.dtype[np.int32]]
    weights: np.ndarray[Any, np.dtype[np.float32]]


def _encode_text(text: str) -> np.ndarray[Any, np.dtype[np.int32]]:
    output = np.zeros(MAX_BYTES, dtype=np.int32)
    encoded = text.encode("utf-8")[:MAX_BYTES]
    output[: len(encoded)] = np.frombuffer(encoded, dtype=np.uint8).astype(np.int32) + 1
    return output


def _lexical_features(text: str) -> tuple[float, ...]:
    length = max(len(text), 1)
    lowered = text.lower()
    return (
        sum(character.isdigit() for character in text) / length,
        sum(character.isalpha() for character in text) / length,
        sum(character.isspace() for character in text) / length,
        float("@" in text),
        float("." in text or "dot" in lowered),
        float("+" in text),
        float("," in text),
        min(len(text) / MAX_BYTES, 1.0),
    )


def encode_card(card: NerCardAnnotation) -> EncodedCard:
    characters = np.zeros((MAX_LINES, MAX_BYTES), dtype=np.int32)
    layout = np.zeros((MAX_LINES, LAYOUT_FEATURES), dtype=np.float32)
    labels = np.zeros(MAX_LINES, dtype=np.int32)
    weights = np.zeros(MAX_LINES, dtype=np.float32)
    tokens = card.tokens[:MAX_LINES]
    mean_height = max(sum(token.box.height for token in tokens) / max(len(tokens), 1), 1e-6)
    for index, token in enumerate(tokens):
        characters[index] = _encode_text(token.ocr_text)
        layout[index] = (
            token.box.x,
            token.box.y,
            token.box.width,
            token.box.height,
            token.confidence,
            index / max(len(tokens) - 1, 1),
            min(token.box.height / mean_height, 4.0) / 4.0,
            1.0,
            *_lexical_features(token.ocr_text),
        )
        labels[index] = TAG_INDEX[token.tag]
        weights[index] = 1.0
    return EncodedCard(characters, layout, labels, weights)


FIRST_NAMES = (
    "Aarav",
    "Aisha",
    "Amelia",
    "Arjun",
    "Daniel",
    "Fatima",
    "Guru",
    "Ishaan",
    "Kavya",
    "Manan",
    "Maya",
    "Neha",
    "Oliver",
    "Priya",
    "Rahul",
    "Riya",
    "Saurabh",
    "Suhas",
)
LAST_NAMES = (
    "Agarwal",
    "Chen",
    "Dass",
    "Iyer",
    "Kapoor",
    "Kathiresan",
    "Mathur",
    "Mehta",
    "Patel",
    "Rao",
    "Sharma",
    "Singh",
    "Stone",
)
COMPANY_WORDS = (
    "Bluewave",
    "Landess",
    "Northstar",
    "Vardhaman",
    "Vertex",
    "Sadhana",
    "Sixonic",
    "Vasundhara",
)
COMPANY_SUFFIXES = (
    "Builders",
    "Enterprises",
    "Infotech Pvt Ltd",
    "Solutions",
    "Technologies",
    "Trading Company",
)
TITLES = (
    "Chief Product Officer",
    "Director",
    "Founder and CEO",
    "Managing Director",
    "Operations Manager",
    "Relationship Manager - Sales",
    "Sales Executive",
)


def _noisy(text: str, rng: random.Random) -> str:
    if rng.random() < 0.42:
        text = text.replace(" ", "")
    if rng.random() < 0.12:
        text = text.upper()
    if rng.random() < 0.08 and len(text) > 5:
        position = rng.randrange(1, len(text) - 1)
        text = text[:position] + text[position + 1 :]
    return text


def synthetic_card(rng: random.Random, index: int) -> EncodedCard:
    name = f"{rng.choice(FIRST_NAMES)} {rng.choice(LAST_NAMES)}"
    company = f"{rng.choice(COMPANY_WORDS)} {rng.choice(COMPANY_SUFFIXES)}"
    title = rng.choice(TITLES)
    emails = [
        f"{name.lower().replace(' ', '.')}@{company.lower().split()[0]}.example"
        for _ in range(1 + int(rng.random() < 0.16))
    ]
    phones = [
        f"+91 {rng.randint(70000, 99999)} {rng.randint(10000, 99999)}"
        for _ in range(1 + int(rng.random() < 0.2))
    ]
    websites = [f"www.{company.lower().split()[0]}.example"] if rng.random() > 0.2 else []
    address = [
        f"{rng.randint(1, 999)}, Market Road,",
        f"Chennai - {rng.randint(600001, 600119)}",
    ]
    identity = [(company, "B-COMPANY"), (name, "B-NAME"), (title, "B-TITLE")]
    if rng.random() < 0.5:
        identity[0], identity[1] = identity[1], identity[0]
    values = identity
    values += [(phone, "B-PHONE") for phone in phones]
    values += [(email, "B-EMAIL") for email in emails]
    values += [(website, "B-WEBSITE") for website in websites]
    if rng.random() > 0.12:
        values += [(address[0], "B-ADDRESS"), (address[1], "I-ADDRESS")]
    if rng.random() < 0.25:
        values.insert(rng.randrange(len(values) + 1), ("Committed to excellence", "O"))

    characters = np.zeros((MAX_LINES, MAX_BYTES), dtype=np.int32)
    layout = np.zeros((MAX_LINES, LAYOUT_FEATURES), dtype=np.float32)
    labels = np.zeros(MAX_LINES, dtype=np.int32)
    weights = np.zeros(MAX_LINES, dtype=np.float32)
    line_height = rng.uniform(0.035, 0.065)
    start_y = rng.uniform(0.06, 0.18)
    for line_index, (text, tag) in enumerate(values[:MAX_LINES]):
        observed = _noisy(text, rng)
        characters[line_index] = _encode_text(observed)
        x = rng.uniform(0.05, 0.18)
        y = min(0.94, start_y + line_index * rng.uniform(0.065, 0.095))
        width = min(0.9 - x, max(0.16, len(observed) * rng.uniform(0.009, 0.016)))
        height = min(0.1, line_height * rng.uniform(0.8, 1.4))
        layout[line_index] = (
            x,
            y,
            width,
            height,
            rng.uniform(0.72, 1.0),
            line_index / max(len(values) - 1, 1),
            min(height / line_height, 4.0) / 4.0,
            1.0,
            *_lexical_features(observed),
        )
        labels[line_index] = TAG_INDEX[tag]
        weights[line_index] = 1.0
    return EncodedCard(characters, layout, labels, weights)


def _stack(cards: list[EncodedCard]) -> tuple[np.ndarray[Any, Any], ...]:
    return (
        np.stack([card.characters for card in cards]),
        np.stack([card.layout for card in cards]),
        np.stack([card.labels for card in cards]),
        np.stack([card.weights for card in cards]),
    )


def _metrics(
    labels: np.ndarray[Any, Any],
    predictions: np.ndarray[Any, Any],
    weights: np.ndarray[Any, Any],
) -> dict[str, Any]:
    mask = weights.reshape(-1) > 0
    truth = labels.reshape(-1)[mask]
    predicted = predictions.reshape(-1)[mask]
    confusion = np.zeros((len(TAGS), len(TAGS)), dtype=np.int64)
    for expected, actual in zip(truth, predicted, strict=True):
        confusion[int(expected), int(actual)] += 1
    per_tag: dict[str, float] = {}
    entity_f1: list[float] = []
    for index, tag in enumerate(TAGS):
        true_positive = confusion[index, index]
        false_positive = confusion[:, index].sum() - true_positive
        false_negative = confusion[index, :].sum() - true_positive
        precision = true_positive / max(true_positive + false_positive, 1)
        recall = true_positive / max(true_positive + false_negative, 1)
        f1 = 2 * precision * recall / max(precision + recall, 1e-9)
        per_tag[tag] = float(f1)
        if tag != "O" and confusion[index, :].sum() > 0:
            entity_f1.append(float(f1))
    return {
        "token_accuracy": float((truth == predicted).mean()),
        "macro_entity_f1": float(np.mean(entity_f1)) if entity_f1 else 0.0,
        "f1_by_tag": per_tag,
        "confusion_matrix": confusion.tolist(),
    }


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train the compact CardLens layout-aware NER")
    parser.add_argument("--registry", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--synthetic-cards", type=int, default=5000)
    parser.add_argument("--real-oversample", type=int, default=30)
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--seed", type=int, default=7319)
    return parser.parse_args()


def main() -> int:
    options = arguments()
    import tensorflow as tf

    random.seed(options.seed)
    np.random.seed(options.seed)
    tf.random.set_seed(options.seed)
    registry_cards, registry_report = discover_registry(options.registry)
    by_split: dict[str, list[EncodedCard]] = {"train": [], "validation": [], "test": []}
    for _, card in registry_cards:
        by_split[card.split].append(encode_card(card))
    if not all(by_split.values()):
        raise SystemExit("registry must contain train, validation and test cards")

    rng = random.Random(options.seed)
    synthetic = [synthetic_card(rng, index) for index in range(options.synthetic_cards)]
    training_cards = synthetic + by_split["train"] * options.real_oversample
    rng.shuffle(training_cards)
    train_chars, train_layout, train_labels, train_weights = _stack(training_cards)
    val_chars, val_layout, val_labels, val_weights = _stack(by_split["validation"])
    test_chars, test_layout, test_labels, test_weights = _stack(by_split["test"])

    frequencies = np.bincount(
        train_labels[train_weights > 0], minlength=len(TAGS)
    ).astype(np.float32)
    class_weights = frequencies.sum() / np.maximum(frequencies * len(TAGS), 1)
    weighted_train = train_weights * class_weights[train_labels]

    character_input = tf.keras.Input((MAX_LINES, MAX_BYTES), dtype="int32", name="characters")
    layout_input = tf.keras.Input((MAX_LINES, LAYOUT_FEATURES), name="layout")
    embedded = tf.keras.layers.Embedding(257, 16, name="character_embedding")(character_input)
    character_patterns = tf.keras.layers.TimeDistributed(
        tf.keras.layers.Conv1D(32, 5, padding="same", activation="relu"),
        name="character_patterns",
    )(embedded)
    character_encoding = tf.keras.layers.TimeDistributed(
        tf.keras.layers.GlobalMaxPooling1D(), name="character_pool"
    )(character_patterns)
    encoded = tf.keras.layers.Dense(64, activation="relu")(character_encoding)
    contextual = tf.keras.layers.Concatenate()([encoded, layout_input])
    contextual = tf.keras.layers.Conv1D(96, 3, padding="same", activation="relu")(contextual)
    contextual = tf.keras.layers.Dropout(0.15)(contextual)
    contextual = tf.keras.layers.Conv1D(
        96, 3, padding="same", dilation_rate=2, activation="relu"
    )(contextual)
    output = tf.keras.layers.Dense(len(TAGS), activation="softmax", name="tags")(contextual)
    model = tf.keras.Model([character_input, layout_input], output)
    model.compile(
        optimizer=tf.keras.optimizers.Adam(2e-3),
        loss="sparse_categorical_crossentropy",
        weighted_metrics=["accuracy"],
    )
    callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor="val_loss", patience=20, restore_best_weights=True
        )
    ]
    history = model.fit(
        [train_chars, train_layout],
        train_labels,
        sample_weight=weighted_train,
        validation_data=([val_chars, val_layout], val_labels, val_weights),
        epochs=options.epochs,
        batch_size=64,
        callbacks=callbacks,
        verbose=2,
    )
    validation_predictions = model.predict([val_chars, val_layout], verbose=0).argmax(axis=2)
    test_predictions = model.predict([test_chars, test_layout], verbose=0).argmax(axis=2)

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()
    options.output.mkdir(parents=True, exist_ok=True)
    model_path = options.output / "layout_ner.tflite"
    model_path.write_bytes(tflite_model)
    metadata = {
        "schema_version": 1,
        "model": "cardlens-layout-ner",
        "tags": list(TAGS),
        "max_lines": MAX_LINES,
        "max_utf8_bytes_per_line": MAX_BYTES,
        "character_encoding": "UTF-8 byte value plus one; zero is padding",
        "layout_features": [
            "x",
            "y",
            "width",
            "height",
            "ocr_confidence",
            "reading_order",
            "relative_height",
            "valid_line",
            "digit_ratio",
            "alphabetic_ratio",
            "whitespace_ratio",
            "has_at_sign",
            "has_dot",
            "has_plus_sign",
            "has_comma",
            "normalized_text_length",
        ],
    }
    (options.output / "layout_ner_metadata.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    metrics = {
        "seed": options.seed,
        "registry": json.loads(registry_report.as_json()),
        "synthetic_training_cards": options.synthetic_cards,
        "real_training_cards": len(by_split["train"]),
        "real_validation_cards": len(by_split["validation"]),
        "real_test_cards": len(by_split["test"]),
        "real_oversample": options.real_oversample,
        "epochs_completed": len(history.history["loss"]),
        "model_bytes": len(tflite_model),
        "validation": _metrics(val_labels, validation_predictions, val_weights),
        "test": _metrics(test_labels, test_predictions, test_weights),
    }
    (options.output / "layout_ner_metrics.json").write_text(
        json.dumps(metrics, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps(metrics, indent=2, sort_keys=True))
    print(model_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
