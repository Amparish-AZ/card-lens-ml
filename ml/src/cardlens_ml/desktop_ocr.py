from __future__ import annotations

import math
from dataclasses import dataclass
from pathlib import Path
from time import perf_counter
from typing import Any, cast

import cv2
import numpy as np
import numpy.typing as npt
import onnxruntime as ort
import pyclipper
import yaml

FloatArray = npt.NDArray[np.float32]
PointArray = npt.NDArray[np.float32]
Uint8Image = npt.NDArray[np.uint8]


@dataclass(frozen=True)
class DesktopOcrLine:
    text: str
    confidence: float
    points: tuple[tuple[float, float], ...]


@dataclass(frozen=True)
class DesktopOcrResult:
    width: int
    height: int
    elapsed_ms: int
    lines: tuple[DesktopOcrLine, ...]


def _order_points(points: PointArray) -> PointArray:
    ordered = np.zeros((4, 2), dtype=np.float32)
    sums = points.sum(axis=1)
    differences = np.diff(points, axis=1).reshape(-1)
    ordered[0] = points[np.argmin(sums)]
    ordered[2] = points[np.argmax(sums)]
    ordered[1] = points[np.argmin(differences)]
    ordered[3] = points[np.argmax(differences)]
    return ordered


def _resize_for_detection(image: Uint8Image, limit: int) -> Uint8Image:
    height, width = image.shape[:2]
    ratio = min(1.0, limit / max(height, width))
    resized_height = max(round(height * ratio / 32) * 32, 32)
    resized_width = max(round(width * ratio / 32) * 32, 32)
    return cast(
        Uint8Image,
        cv2.resize(image, (resized_width, resized_height), interpolation=cv2.INTER_LINEAR),
    )


def _detection_tensor(image: Uint8Image) -> FloatArray:
    value = image.astype(np.float32) / 255.0
    mean = np.asarray([0.485, 0.456, 0.406], dtype=np.float32)
    std = np.asarray([0.229, 0.224, 0.225], dtype=np.float32)
    value = (value - mean) / std
    return cast(FloatArray, np.transpose(value, (2, 0, 1))[None, ...])


def _box_score(probability: FloatArray, points: PointArray) -> float:
    height, width = probability.shape
    x_min = max(0, math.floor(float(points[:, 0].min())))
    x_max = min(width - 1, math.ceil(float(points[:, 0].max())))
    y_min = max(0, math.floor(float(points[:, 1].min())))
    y_max = min(height - 1, math.ceil(float(points[:, 1].max())))
    if x_max <= x_min or y_max <= y_min:
        return 0.0
    mask = np.zeros((y_max - y_min + 1, x_max - x_min + 1), dtype=np.uint8)
    shifted = points.copy()
    shifted[:, 0] -= x_min
    shifted[:, 1] -= y_min
    cv2.fillPoly(mask, [shifted.astype(np.int32)], (1,))
    region = probability[y_min : y_max + 1, x_min : x_max + 1]
    return float(cv2.mean(region, mask=mask)[0])


def _unclip(points: PointArray, ratio: float) -> PointArray | None:
    area = abs(float(cv2.contourArea(points)))
    perimeter = float(cv2.arcLength(points, True))
    if area <= 0 or perimeter <= 0:
        return None
    distance = area * ratio / perimeter
    scale = 1024.0
    path = [(round(float(x) * scale), round(float(y) * scale)) for x, y in points]
    offset = pyclipper.PyclipperOffset()
    offset.AddPath(path, pyclipper.JT_ROUND, pyclipper.ET_CLOSEDPOLYGON)
    solutions = offset.Execute(distance * scale)
    if not solutions:
        return None
    largest = max(solutions, key=lambda polygon: abs(pyclipper.Area(polygon)))
    return np.asarray(largest, dtype=np.float32) / scale


def _detect_boxes(
    probability: FloatArray,
    *,
    original_width: int,
    original_height: int,
    threshold: float = 0.25,
    box_threshold: float = 0.45,
    unclip_ratio: float = 1.6,
) -> list[PointArray]:
    mask = (probability > threshold).astype(np.uint8) * 255
    contours, _ = cv2.findContours(mask, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    prediction_height, prediction_width = probability.shape
    scale_x = original_width / prediction_width
    scale_y = original_height / prediction_height
    boxes: list[PointArray] = []
    for contour in contours[:3000]:
        rect = cv2.minAreaRect(contour)
        if min(rect[1]) < 3:
            continue
        points = _order_points(cv2.boxPoints(rect).astype(np.float32))
        if _box_score(probability, points) < box_threshold:
            continue
        expanded = _unclip(points, unclip_ratio)
        if expanded is None:
            continue
        expanded_rect = cv2.minAreaRect(expanded)
        if min(expanded_rect[1]) < 5:
            continue
        scaled = _order_points(cv2.boxPoints(expanded_rect).astype(np.float32))
        scaled[:, 0] = np.clip(np.rint(scaled[:, 0] * scale_x), 0, original_width)
        scaled[:, 1] = np.clip(np.rint(scaled[:, 1] * scale_y), 0, original_height)
        width = max(np.linalg.norm(scaled[0] - scaled[1]), np.linalg.norm(scaled[2] - scaled[3]))
        height = max(np.linalg.norm(scaled[0] - scaled[3]), np.linalg.norm(scaled[1] - scaled[2]))
        if width > 3 and height > 3:
            boxes.append(scaled)
    return sorted(boxes, key=lambda box: (round(float(box[0, 1]) / 10), float(box[0, 0])))


def _crop_quad(image: Uint8Image, points: PointArray) -> Uint8Image:
    ordered = _order_points(cv2.boxPoints(cv2.minAreaRect(points)).astype(np.float32))
    width = max(np.linalg.norm(ordered[0] - ordered[1]), np.linalg.norm(ordered[2] - ordered[3]))
    height = max(np.linalg.norm(ordered[0] - ordered[3]), np.linalg.norm(ordered[1] - ordered[2]))
    output_width = max(1, round(float(width)))
    output_height = max(1, round(float(height)))
    destination = np.asarray(
        [[0, 0], [output_width, 0], [output_width, output_height], [0, output_height]],
        dtype=np.float32,
    )
    transform = cv2.getPerspectiveTransform(ordered, destination)
    crop = cast(
        Uint8Image,
        cv2.warpPerspective(
            image,
            transform,
            (output_width, output_height),
            flags=cv2.INTER_CUBIC,
            borderMode=cv2.BORDER_REPLICATE,
        ),
    )
    if crop.shape[0] / max(crop.shape[1], 1) >= 1.5:
        crop = cast(Uint8Image, cv2.rotate(crop, cv2.ROTATE_90_COUNTERCLOCKWISE))
    return crop


def _recognition_tensor(crops: list[Uint8Image]) -> FloatArray:
    resized: list[FloatArray] = []
    widths: list[int] = []
    for crop in crops:
        rgb = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
        width = min(3200, math.ceil(48 * rgb.shape[1] / max(rgb.shape[0], 1)))
        value = cv2.resize(rgb, (width, 48), interpolation=cv2.INTER_LINEAR).astype(np.float32)
        resized.append(cast(FloatArray, value / 127.5 - 1.0))
        widths.append(width)
    max_width = max(widths)
    batch = np.zeros((len(crops), 3, 48, max_width), dtype=np.float32)
    for index, value in enumerate(resized):
        batch[index, :, :, : widths[index]] = np.transpose(value, (2, 0, 1))
    return batch


def _decode_ctc(output: FloatArray, characters: list[str]) -> list[tuple[str, float]]:
    indices = output.argmax(axis=2)
    probabilities = output.max(axis=2)
    decoded: list[tuple[str, float]] = []
    for sequence, scores in zip(indices, probabilities, strict=True):
        previous = -1
        text: list[str] = []
        kept_scores: list[float] = []
        for raw_index, raw_score in zip(sequence, scores, strict=True):
            index = int(raw_index)
            if index != 0 and index != previous and index - 1 < len(characters):
                text.append(characters[index - 1])
                kept_scores.append(float(raw_score))
            previous = index
        decoded.append(("".join(text), sum(kept_scores) / len(kept_scores) if kept_scores else 0))
    return decoded


class DesktopPaddleOcr:
    def __init__(self, detector: Path, recognizer: Path, recognizer_yaml: Path) -> None:
        options = ort.SessionOptions()
        options.intra_op_num_threads = 4
        options.inter_op_num_threads = 1
        self._detector = ort.InferenceSession(
            str(detector), sess_options=options, providers=["CPUExecutionProvider"]
        )
        self._recognizer = ort.InferenceSession(
            str(recognizer), sess_options=options, providers=["CPUExecutionProvider"]
        )
        config = cast(dict[str, Any], yaml.safe_load(recognizer_yaml.read_text(encoding="utf-8")))
        postprocess = cast(dict[str, Any], config["PostProcess"])
        self._characters = [str(character) for character in postprocess["character_dict"]]

    def recognize(self, image_path: Path, *, limit_side: int = 1600) -> DesktopOcrResult:
        started = perf_counter()
        raw_image = cv2.imread(str(image_path), cv2.IMREAD_COLOR)
        if raw_image is None:
            raise ValueError(f"unable to decode image: {image_path}")
        image = cast(Uint8Image, raw_image)
        original_height, original_width = image.shape[:2]
        resized = _resize_for_detection(image, limit_side)
        detector_input = self._detector.get_inputs()[0].name
        raw_detection = self._detector.run(None, {detector_input: _detection_tensor(resized)})[0]
        probability = cast(FloatArray, np.asarray(raw_detection[0, 0], dtype=np.float32))
        boxes = _detect_boxes(
            probability,
            original_width=original_width,
            original_height=original_height,
        )
        crops = [_crop_quad(image, box) for box in boxes]
        recognized: list[tuple[str, float]] = []
        recognizer_input = self._recognizer.get_inputs()[0].name
        for start in range(0, len(crops), 4):
            batch = crops[start : start + 4]
            raw_recognition = self._recognizer.run(
                None, {recognizer_input: _recognition_tensor(batch)}
            )[0]
            recognized.extend(
                _decode_ctc(np.asarray(raw_recognition, dtype=np.float32), self._characters)
            )
        lines = tuple(
            DesktopOcrLine(
                text=text.strip(),
                confidence=confidence,
                points=tuple((float(x), float(y)) for x, y in box),
            )
            for box, (text, confidence) in zip(boxes, recognized, strict=True)
            if text.strip() and confidence >= 0.25
        )
        return DesktopOcrResult(
            width=original_width,
            height=original_height,
            elapsed_ms=round((perf_counter() - started) * 1000),
            lines=lines,
        )
