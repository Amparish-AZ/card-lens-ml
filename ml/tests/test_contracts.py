import pytest

from cardlens_ml.contracts import CardAnnotation, ContractError


def test_card_contract_accepts_missing_optional_fields() -> None:
    card = CardAnnotation.from_mapping(
        {
            "schema_version": 1,
            "card_id": "card-1",
            "image": "images/card-1.jpg",
            "split": "train",
            "lines": [
                {
                    "ocr_text": "Example Labs",
                    "truth_text": "Example Labs",
                    "label": "company",
                    "box": [0.1, 0.1, 0.4, 0.1],
                }
            ],
        }
    )
    assert card.lines[0].label == "company"


def test_card_contract_rejects_box_outside_image() -> None:
    with pytest.raises(ContractError, match="inside"):
        CardAnnotation.from_mapping(
            {
                "schema_version": 1,
                "card_id": "card-1",
                "image": "images/card-1.jpg",
                "split": "train",
                "lines": [
                    {
                        "ocr_text": "Example Labs",
                        "truth_text": "Example Labs",
                        "label": "company",
                        "box": [0.8, 0.1, 0.4, 0.1],
                    }
                ],
            }
        )

